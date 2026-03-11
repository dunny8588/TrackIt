<template>
  <div class="map-wrapper absolute-top-left absolute-bottom-right">
    <div id="map" :style="{height: mapHeight}">
      <q-resize-observer @resize="onResize" />
    </div>
    <queue
      ref="queue"
      v-if="Object.keys(messages).length && activeDevicesID.length"
      :activeDevicesID="activeDevicesID"
      :needShowMessages="params.needShowMessages"
      :needShowPlayer="params.needShowPlayer"
      :messages="allMessages"
      :selectedDeviceId="selectedDeviceId"
      :telemetryDeviceId="telemetryDeviceId"
      :date="date"
      :player="player"
      @player-value="data => playProcess(data, 'value')"
      @player-play="data => playProcess(data, 'play')"
      @player-pause="data => playProcess(data, 'pause')"
      @player-stop="data => playProcess(data, 'stop')"
      @player-speed="playerSpeedChangeHandler"
      @player-mode="playerModeChange"
      @change-need-show-messages="(flag) => {$emit('change-need-show-messages', flag)}"
      @queue-created="$emit('queue-created')"
      @update-color="updateColorHandler"
      @view-on-map="viewOnMapHandler"
    />
    <color-modal ref="colorModal" v-model="color"/>
  </div>
</template>

<script>
import * as L from 'leaflet'
import 'leaflet-geometryutil'
import 'leaflet/dist/leaflet.css'
import 'leaflet.marker.slideto'
import 'leaflet.polylinemeasure/Leaflet.PolylineMeasure.css'
import 'leaflet.polylinemeasure/Leaflet.PolylineMeasure'
import lefleatSnake from '../assets/lefleat-snake'
import 'leaflet.gridlayer.googlemutant'
import Vue from 'vue'
import Queue from './Queue.vue'
import ColorModal from './ColorModal'
import { mapState } from 'vuex'
import devicesMessagesModule from 'qvirtualscroll/src/store/modules/devicesMessages'
import { colors, debounce } from 'quasar'
import getIconHTML from '../assets/getIconHTML.js'
import { getFromStore, setToStore } from '../mixins/store'

lefleatSnake(L)

/**
 * Map Component
 * 
 * Displays device locations and tracks on an interactive map
 * 
 * Features:
 * - Shows devices as markers with colored icons based on device type
 * - Displays device tracks as polylines
 * - Auto-zooms to fit all visible points with padding when:
 *   - Data refreshes
 *   - A new device is selected
 *   - Date range changes
 *   - New data points are received
 * - Interactive device following
 * - Position history playback
 * - Info popups for device details
 */
export default {
  name: 'Map',
  props: [
    'params',
    'devicesColors',
    'selectedDeviceId',
    'isSelectedDeviceFollowed',
    'activeDevices',
    'delay',
    'date'
  ],
  data () {
    return {
      map: null,
      flyToZoom: 16, // Reduced from 18 to 16 to provide more buffer around points
      isFlying: null,
      markers: {},
      tracks: {},
      telemetryDeviceId: -1,
      activeDevicesID: [],
      devicesState: {},
      selected: null,
      currentColorModel: '#fff',
      currentColorId: 0,
      player: {
        currentMsgIndex: null,
        speed: 10,
        status: 'stop',
        mode: 'time',
        tailInterval: 0
      }
    }
  },
  computed: {
    ...mapState({
      messages (state) {
        return this.activeDevicesID.reduce((result, id) => {
          result[id] = state.messages[id].messages.reduce((result, message, index) => {
            // Filter out GTPNA messages
            if (message['report.code'] === 'GTPNA') {
              return result;
            }
            
            // Filter out LBS points if the toggle is off
            if (!this.params.needShowLBSPoints && 
                message['position.source'] && 
                message['position.source'].toLowerCase() === 'lbs') {
              return result;
            }
            
            if (!!message['position.latitude'] && !!message['position.longitude']) {
              // pass message to the map only if it has position.latitude and position.longitude
              if (!this.params.needShowInvalidPositionMessages) {
                // don't pass messages with position.valid=false to the map
                if (!message.hasOwnProperty('position.valid') || (message.hasOwnProperty('position.valid') && message['position.valid'] === true)) {
                  // pass messages to the map disregarding pasition.valid parameter
                  Object.defineProperty(message, 'x-flespi-message-index', {
                    value: index,
                    enumerable: false
                  })
                  result.push(message)
                }
              } else {
                // pass messages to the map disregarding pasition.valid parameter
                Object.defineProperty(message, 'x-flespi-message-index', {
                  value: index,
                  enumerable: false
                })
                result.push(message)
              }
            }
            return result
          }, [])
          return result
        }, {})
      },
      allMessages (state) {
        return this.activeDevicesID.reduce((result, id) => {
          // Filter out GTPNA messages from the messages list
          // Also filter out LBS points if the toggle is off
          result[id] = state.messages[id].messages.filter(message => 
            message['report.code'] !== 'GTPNA' && 
            (this.params.needShowLBSPoints || 
             !message['position.source'] || 
             message['position.source'].toLowerCase() !== 'lbs')
          )
          return result
        }, {})
      },
      telemetry: (state) => state.telemetry
    }),
    color: {
      get () { return this.currentColorModel },
      set (color) {
        this.updateColorHandler({ id: this.currentColorId, color })
        this.currentColorModel = color
      }
    },
    mapHeight () {
      let value = '100%'
      // if no devices are selected - map fills all screen height
      if (!this.activeDevices.length) { return value }
      // if nore than one device is selected - there is panel with devices' names tabs
      if (this.params.needShowPlayer) {
        value = 'calc(100% - 48px)'
      }
      return value
    }
  },
  methods: {
    /**
     * Auto-zoom the map to fit all visible points with padding
     * 
     * This method:
     * 1. Collects all visible points from all active devices
     * 2. Filters out points based on current visibility settings (LBS points, invalid positions)
     * 3. Creates a bounds object that encompasses all points
     * 4. Adds padding around the points to ensure they're not at the edge of the map
     * 5. Sets a maximum zoom level to prevent excessive zooming on single points
     * 
     * Used when:
     * - Messages are updated or refreshed
     * - A device is selected
     * - Date range changes
     * - Initial device setup
     */
    autoZoomToFitPoints() {
      // Only proceed if we have a map and there are active device IDs
      if (!this.map || !this.activeDevicesID.length) return;
      
      // Collect all valid point coordinates from all devices
      const allPoints = this.activeDevicesID.reduce((points, id) => {
        if (this.messages[id] && this.messages[id].length) {
          const devicePoints = this.messages[id].filter(msg => {
            // Only include points with valid coordinates
            if (!msg['position.latitude'] || !msg['position.longitude']) return false;
            
            // Skip LBS points if the toggle is off
            if (!this.params.needShowLBSPoints && 
                msg['position.source'] && 
                msg['position.source'].toLowerCase() === 'lbs') {
              return false;
            }
            
            // Skip invalid positions if the toggle is off
            if (!this.params.needShowInvalidPositionMessages && 
                msg.hasOwnProperty('position.valid') && 
                msg['position.valid'] === false) {
              return false;
            }
            
            return true;
          }).map(msg => [msg['position.latitude'], msg['position.longitude']]);
          
          return points.concat(devicePoints);
        }
        return points;
      }, []);
      
      // If we have points, fit the map to them with padding
      if (allPoints.length) {
        try {
          // Create a bounds object from all points
          const bounds = L.latLngBounds(allPoints);
          
          // Add generous padding to account for UI elements:
          // - Top: more padding for date selector
          // - Left: more padding for message boxes
          // - Right: padding for any controls
          // - Bottom: padding for player controls
          this.map.fitBounds(bounds, {
            padding: [
              120,  // Top padding (px) - more space for date selector
              200   // Left/right/bottom padding (px) - for message boxes and controls
            ],
            maxZoom: 18,      // Don't zoom in too far
            animate: true     // Smooth animation
          });
          
          console.log('Auto-zoomed map to fit', allPoints.length, 'points');
        } catch (e) {
          console.error('Error auto-zooming map:', e);
        }
      } else {
        console.log('No valid points found for auto-zoom');
      }
    },
    
    createInfoBox(message, position) {
      console.log('createInfoBox called with message:', message);
      
      if (!message) {
        console.error('No message data provided to createInfoBox');
        return;
      }
      
      // Format timestamp in "Sun 25 Dec 2024 hh:mm:ss" format
      const timestamp = message.timestamp ? 
        formatCustomDate(new Date(message.timestamp * 1000)) : 'N/A';
        
      // Helper function to format date in the requested format
      function formatCustomDate(date) {
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        
        const dayName = days[date.getDay()];
        const day = date.getDate();
        const month = months[date.getMonth()];
        const year = date.getFullYear();
        
        // Add leading zeros to hours, minutes, seconds
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        const seconds = String(date.getSeconds()).padStart(2, '0');
        
        return `${dayName} ${day} ${month} ${year} ${hours}:${minutes}:${seconds}`;
      }
      
      // Get battery level
      const batteryLevel = message['battery.level'] !== undefined ? 
        `${message['battery.level']}%` : 'N/A';
        
      // Get position source (GPS or LBS)
      const positionSource = message['position.source'] ? 
        message['position.source'].toUpperCase() : 'N/A';
      
      // Get power reason text
      const powerReason = message['power.reason.text'] || 'N/A';
      
      // Get satellites count for GPS points
      const satellites = message['position.satellites'] !== undefined ? 
        message['position.satellites'] : 'N/A';
      
      // Generate Google Maps link
      const lat = message['position.latitude'];
      const lng = message['position.longitude'];
      const googleMapsUrl = `https://www.google.com/maps?q=${lat},${lng}`;
      
      // Get lastCmdQueue and lastCmdExec values
      const lastCmdQueue = message['lastCmdQueue'] !== undefined ? 
        message['lastCmdQueue'] : 'N/A';
        
      const lastCmdExec = message['lastCmdExec'] !== undefined ? 
        message['lastCmdExec'] : 'N/A';
        
      // Create HTML content for info box
      let content = `
        <div class="info-box">
          <div class="info-box-header">
            <span class="info-box-close">&times;</span>
          </div>
          <table class="info-box-content">
            <tr>
              <td><strong>Time:</strong></td>
              <td>${timestamp}</td>
            </tr>
            <tr>
              <td><strong>Source:</strong></td>
              <td>${positionSource}</td>
            </tr>`;
              
      // Add satellites row only for GPS points
      if (positionSource === 'GPS' && satellites !== 'N/A') {
        content += `
            <tr>
              <td><strong># Satellites:</strong></td>
              <td>${satellites}</td>
            </tr>`;
      }
      
      content += `
            <tr>
              <td><strong>Battery:</strong></td>
              <td>${batteryLevel}</td>
            </tr>
            <tr>
              <td><strong>Power:</strong></td>
              <td>${powerReason}</td>
            </tr>
            <tr>
              <td><strong>Last Cmd Queue:</strong></td>
              <td>${lastCmdQueue}</td>
            </tr>
            <tr>
              <td><strong>Last Cmd Exec:</strong></td>
              <td>${lastCmdExec}</td>
            </tr>
            <tr>
              <td colspan="2">
                <a href="${googleMapsUrl}" target="_blank" class="info-box-link">
                  Open in Google Maps
                </a>
              </td>
            </tr>
          </table>
        </div>
      `;
      
      // Create a simple fixed-position div that we'll add to the map
      const infoBoxDiv = document.createElement('div');
      infoBoxDiv.className = 'info-box-container';
      infoBoxDiv.innerHTML = content;
      
      // Add click event to close button
      const closeBtn = infoBoxDiv.querySelector('.info-box-close');
      if (closeBtn) {
        closeBtn.addEventListener('click', () => {
          if (infoBoxDiv.parentNode) {
            infoBoxDiv.parentNode.removeChild(infoBoxDiv);
          }
          this.map.infoBox = null;
        });
      }
      
      // Remove any existing info box
      if (this.map.infoBox) {
        const oldBox = document.querySelector('.info-box-container');
        if (oldBox && oldBox.parentNode) {
          oldBox.parentNode.removeChild(oldBox);
        }
        this.map.infoBox = null;
      }
      
      // Add the info box to the map container
      const mapContainer = document.getElementById('map');
      if (mapContainer) {
        mapContainer.appendChild(infoBoxDiv);
        this.map.infoBox = infoBoxDiv;
      }
    },
    
    initMap () {
      if (!this.map) {
        // OpenStreetMap layers with increased max zoom
        let osm = L.tileLayer('//{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { 
          minZoom: 3, 
          maxZoom: 22, // Increased max zoom
          noWrap: true 
        })
        
        this.map = L.map('map', {
          center: [51.50853, -0.12574],
          zoom: 3,
          maxBounds: [
            [90, -180],
            [-90, 180]
          ],
          maxZoom: 22, // Increased max zoom level
          layers: [osm]
        })
        
        this.map.addEventListener('zoom', e => {
          if (!e.flyTo) {
            this.flyToZoom = e.target.getZoom()
          }
        })
        
        this.map.on('click', e => {
          console.log('Map clicked');
          this.mapClickHandler(e);
        })
        
        // Traditional map layers
        let satellite = L.tileLayer('//server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', { 
          minZoom: 3, 
          maxZoom: 22, // Increased max zoom
          noWrap: true, 
          attribution: '© ArcGIS' 
        })
        
        let opentopo = L.tileLayer('//{s}.tile.opentopomap.org/{z}/{x}/{y}.png', { 
          minZoom: 3, 
          maxZoom: 19, 
          attribution: 'Map data: © OpenStreetMap contributors, SRTM | Map style: © OpenTopoMap (CC-BY-SA)', 
          noWrap: true
        })
        
        let osmtransp = L.tileLayer.wms('//{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
          layers: 'semitransparent',
          transparent: 'true',
          format: 'image/png',
          maxZoom: 22, // Increased max zoom
          opacity: 0.5
        })
        
        // Google Maps layers
        let googleRoadmap = L.gridLayer.googleMutant({
          type: 'roadmap',
          maxZoom: 22, // Google provides up to zoom level 22
          attribution: '© Google Maps'
        })
        
        let googleSatellite = L.gridLayer.googleMutant({
          type: 'satellite',
          maxZoom: 22,
          attribution: '© Google Maps'
        })
        
        let googleHybrid = L.gridLayer.googleMutant({
          type: 'hybrid',
          maxZoom: 22,
          attribution: '© Google Maps'
        })
        
        let googleTerrain = L.gridLayer.googleMutant({
          type: 'terrain',
          maxZoom: 22,
          attribution: '© Google Maps'
        })
        
        // All base map layers
        var baseMaps = {
          'OpenStreetMap': osm,
          'Satellite (ArcGIS)': satellite,
          'OpenTopoMap': opentopo,
          'Google Roads': googleRoadmap,
          'Google Satellite': googleSatellite,
          'Google Hybrid': googleHybrid,
          'Google Terrain': googleTerrain
        }
        
        // Overlay layers
        var overlayMaps = {
          'OpenStreetMaps (0.5)': osmtransp
        }
        
        L.control.layers(baseMaps, overlayMaps).addTo(this.map)
        L.control.polylineMeasure({
          position: 'topleft',
          showBearings: false,
          clearMeasurementsOnStop: false,
          showUnitControl: false,
          showClearControl: true,
          measureControlTitleOn: 'Turn on ruler',
          measureControlTitleOff: 'Turn off ruler',
          tooltipTextFinish: 'Click to <b>finish line</b><br>',
          tooltipTextDelete: 'Press SHIFT-key and click to <b>delete point</b>',
          tooltipTextMove: 'Click and drag to <b>move point</b><br>',
          tooltipTextResume: '<br>Press CTRL-key and click to <b>resume line</b>',
          tooltipTextAdd: 'Press CTRL-key and click to <b>add point</b>'
        }).addTo(this.map)
      }
    },
    flyToWithHideTracks (position, zoom) {
      const disabledLayout = []
      let isFlying = false
      this.map.once('zoomstart', e => {
        this.isFlying = true
        const fromZoom = e.target._zoom
        if (fromZoom !== zoom) {
          isFlying = true
          Object.keys(this.tracks).forEach((trackId) => {
            const track = this.tracks[trackId]
            if (track instanceof L.Polyline) {
              if (track.tail && track.tail instanceof L.Polyline && this.map.hasLayer(track.tail)) {
                this.map.removeLayer(track.tail)
                disabledLayout.push(track.tail)
              }
              if (track.overview && track.overview instanceof L.Polyline && this.map.hasLayer(track.overview)) {
                this.map.removeLayer(track.overview)
                disabledLayout.push(track.overview)
              }
              if (track.overview && this.map.hasLayer(track.overview)) {
                this.map.removeLayer(track)
                disabledLayout.push(track)
              }
            }
          })
        }
      })
      this.map.once('zoomend', e => {
        this.isFlying = false
        if (isFlying) {
          disabledLayout.forEach((layer) => {
            this.map.addLayer(layer)
          })
        }
      })

      this.map.flyTo(position, zoom)
    },
    generateIcon (id, name, color, positionSource = null, isMostRecent = false, sequenceNumber = null) {
      return L.divIcon({
        className: `my-div-icon icon-${id}`,
        iconSize: new L.Point(20, 20),
        html: getIconHTML(name, color, this.params.needShowNamesOnMap, positionSource, isMostRecent, sequenceNumber)
      })
    },
    getAccuracyParams (message) {
      const position = [message['position.latitude'], message['position.longitude']],
        // Use position.accuracy if available, otherwise fall back to hdop/pdop
        accuracy = message['position.accuracy'] || message['position.hdop'] || message['position.pdop'] || 0,
        positionSource = message['position.source'] || null,
        // Set circle color based on position source: black for GPS, orange for LBS
        circleColor = positionSource ? 
                     (positionSource.toLowerCase() === 'gps' ? '#000000' : 
                      positionSource.toLowerCase() === 'lbs' ? '#FFA500' : '#444') : '#444',
        circleStyle = {
          stroke: true,
          color: circleColor,
          weight: 3,
          opacity: 0.7,
          fillOpacity: 0.15,
          fillColor: circleColor,
          clickable: false
        }
      return { position, accuracy, circleStyle, positionSource }
    },
    updateMarkerDirection (id, dir) {
      if (dir) {
        // Update main marker direction
        const mainElement = document.querySelector(`.icon-${id} .my-div-icon__inner`)
        if (mainElement) {
          mainElement.style.transform = `rotate(${(dir || 0)}deg)`
        }
      }
    },
    updateMarker (id, pos, dir, message = null) {
      if (!this.markers[id] || !this.markers[id].main) {
        return;
      }
      
      this.updateMarkerDirection(id, dir)
      this.markers[id].main.setLatLng(pos).update()
      
      // Update position source if message is provided
      if (message) {
        const positionSource = message['position.source'] || null
        
        if (positionSource && this.devicesState[id].lastPositions) {
          const source = positionSource.toLowerCase()
          const messageIndex = message['x-flespi-message-index'] || 0
          
          if (source === 'gps' || source === 'lbs') {
            // Check if this is a new most recent point for this source type
            const isMostRecent = this.devicesState[id].lastPositions[source] === null || 
                                messageIndex > this.devicesState[id].lastPositions[source]
            
            if (isMostRecent) {
              this.devicesState[id].lastPositions[source] = messageIndex
            }
            
            // Update main marker icon with new position source and most recent status
            this.markers[id].main.setIcon(this.generateIcon(
              id, 
              this.markers[id].main.options.title, 
              this.markers[id].color, 
              positionSource, 
              isMostRecent,
              0 // Use "0" for current position
            ))
            this.markers[id].main.positionSource = positionSource
          }
        }
      }
    },
    initMarker (id, name, position) {
      const lastMessage = this.messages[id][this.messages[id].length - 1],
        direction = lastMessage['position.direction'] ? lastMessage['position.direction'] : 0,
        positionSource = lastMessage['position.source'] || null,
        currentColor = this.tracks[id] && this.tracks[id].options ? this.tracks[id].options.color : this.markers[id] ? this.markers[id].color : this.devicesColors[id]
      
      // Initialize positions tracking for this device
      if (!this.devicesState[id].lastPositions) {
        this.devicesState[id].lastPositions = { gps: null, lbs: null }
      }
      
      // Initialize markers collection if not exists
      if (!this.markers[id]) {
        this.markers[id] = {};
      }
      
      // Create main marker for current position (for compatibility with existing code)
      // Use "0" as the sequence number for the current/latest position
      // Set highest z-index (1100) to ensure current position is always on top
      this.markers[id].main = L.marker(position, {
        icon: this.generateIcon(id, name, currentColor, positionSource, true, 0),
        draggable: false,
        title: name,
        zIndexOffset: 1100 // Higher than any historical point to always be on top
      });
      
      this.markers[id].main.id = id;
      this.markers[id].main.color = currentColor;
      this.markers[id].main.positionSource = positionSource;
      this.markers[id].id = id;
      this.markers[id].color = currentColor;
      
      // Create collections for all position points and accuracy circles
      this.markers[id].points = {
        gps: [],
        lbs: []
      };
      
      this.markers[id].accuracyCircles = {
        gps: [],
        lbs: []
      };
      
      // Create the main accuracy circle
      const { position: pos, accuracy, circleStyle } = this.getAccuracyParams(lastMessage)
      this.markers[id].accuracy = L.circle(pos, accuracy, circleStyle)
      this.markers[id].accuracy.addTo(this.map)
      
      // Initialize all points from messages
      this.initAllPoints(id);
      
      this.markers[id].main.on('add', e => {
        console.log('Main marker added for device:', id);
        this.updateMarkerDirection(id, direction)
        if (this.messages[id] && this.messages[id].length && this.selectedDeviceId === parseInt(id)) {
          // selected logic
        }
      })
      this.markers[id].main.on('click', e => {
        console.log('Main marker clicked for device:', id);
        this.telemetryDeviceId = parseInt(id)
        this.$emit('update-telemetry-device-id', this.telemetryDeviceId)
      })
      this.markers[id].main.on('move', e => {
        console.log('Main marker moved for device:', id);
        if (this.player.status === 'stop') {
          this.updateMarkerDirection(id, this.messages[id][this.messages[id].length - 1]['position.direction'])
        }
      })
      this.markers[id].main.on('contextmenu', e => {
        console.log('Main marker context menu for device:', id);
        this.currentColorId = id
        this.currentColorModel = this.markers[id].color
        this.$refs.colorModal.show()
      })
      this.markers[id].main.addTo(this.map)
    },
    // Initialize all points for a device with sequential numbering
    initAllPoints(id) {
      if (!this.messages[id] || !this.messages[id].length) {
        return;
      }
      
      // Clear existing points first
      this.clearAllPoints(id);
      
      // Find the last indices for GPS and LBS to mark them as most recent
      const lastGpsIndex = this.findLastIndex(this.messages[id], msg => 
        msg['position.source'] && msg['position.source'].toLowerCase() === 'gps');
      
      const lastLbsIndex = this.findLastIndex(this.messages[id], msg => 
        msg['position.source'] && msg['position.source'].toLowerCase() === 'lbs');
      
      // Store the latest indices
      if (lastGpsIndex !== -1) {
        this.devicesState[id].lastPositions.gps = lastGpsIndex;
      }
      
      if (lastLbsIndex !== -1) {
        this.devicesState[id].lastPositions.lbs = lastLbsIndex;
      }
      
      // Create filtered arrays of valid GPS and LBS points
      const validGpsPoints = [];
      const validLbsPoints = [];
      
      // First pass: collect valid points
      this.messages[id].forEach((message, index) => {
        if (message['position.latitude'] && message['position.longitude']) {
          const positionSource = message['position.source'];
          if (!positionSource) return;
          
          const source = positionSource.toLowerCase();
          if (source !== 'gps' && source !== 'lbs') return;
          
          // Skip LBS points if the toggle is off
          if (source === 'lbs' && !this.params.needShowLBSPoints) return;
          
          // Add point to appropriate array
          if (source === 'gps') {
            validGpsPoints.push({ message, index });
          } else if (source === 'lbs') {
            validLbsPoints.push({ message, index });
          }
        }
      });
      
      // Sort each array by timestamp descending (newest first)
      const sortPoints = (points) => {
        return points.sort((a, b) => {
          return b.message.timestamp - a.message.timestamp;
        });
      };
      
      const sortedGpsPoints = sortPoints(validGpsPoints);
      const sortedLbsPoints = sortPoints(validLbsPoints);
      
      // Create markers for GPS points with sequential numbering
      sortedGpsPoints.forEach((point, sequenceIndex) => {
        const { message, index } = point;
        const position = [message['position.latitude'], message['position.longitude']];
        const isMostRecent = index === lastGpsIndex;
        
        // Simplified approach to numbering:
        // Always start from 1 for historical points
        // Keep the main marker as 0
        // Don't skip points, but the most recent might overlap with main marker
        const sequenceNumber = sequenceIndex + 1; // Start from 1 for all historical points
        
        // Create marker for this point
        // Set z-index based on sequence number to ensure newer points appear on top
        // Higher z-index values appear on top, so we use 1000 - sequenceNumber
        // This ensures sequence 1 is on top of sequence 2, etc.
        const zIndexOffset = 1000 - sequenceNumber; // Highest numbers for newest points
        
        const pointMarker = L.marker(position, {
          icon: this.generateIcon(
            id, 
            this.markers[id].main.options.title, 
            this.markers[id].color, 
            message['position.source'], 
            isMostRecent,
            sequenceNumber
          ),
          draggable: false,
          messageIndex: index,
          zIndexOffset: zIndexOffset // This controls stacking order
        });
        
        // Add click event to show message details
        pointMarker.on('click', e => {
          console.log('Point marker clicked:', message);
            
            // Remove previous message point and info box
            if (this.map.messagePoint) { this.map.messagePoint.remove() }
            if (this.map.messageAccuracy) { this.map.messageAccuracy.remove(); this.map.messageAccuracy = null; }
            if (this.map.infoBox) { this.map.infoBox.remove(); this.map.infoBox = null; }
            
            // Create a pulse effect
            let pulseColor = message['position.source'].toLowerCase() === 'gps' ? '#000000' : '#FFA500';
            this.map.messagePoint = L.marker(position, {
              icon: L.divIcon({
                className: `my-round-marker-wrapper`,
                iconSize: new L.Point(10, 10),
                html: `<div class="my-round-marker" style="background-color: ${pulseColor};"></div>`
              })
            });
            this.map.messagePoint.addTo(this.map);
            
            // Show accuracy circle
            if (message['position.accuracy']) {
              const { accuracy, circleStyle } = this.getAccuracyParams(message);
              this.map.messageAccuracy = L.circle(position, accuracy, circleStyle);
              this.map.messageAccuracy.addTo(this.map);
            }
            
            // Create and show info box
            this.createInfoBox(message, position);
            
            // Select the message in the UI
            this.$store.commit(`messages/${id}/setSelected`, [index]);
          });
          
          // Add to the map and store in our collections
          pointMarker.addTo(this.map);
          this.markers[id].points['gps'].push(pointMarker);
          
          // Create accuracy circle if needed
          if (message['position.accuracy']) {
            const { accuracy, circleStyle } = this.getAccuracyParams(message);
            const circle = L.circle(position, accuracy, circleStyle);
            circle.addTo(this.map);
            this.markers[id].accuracyCircles['gps'].push(circle);
          }
        });
        
        // Create markers for LBS points with sequential numbering
        sortedLbsPoints.forEach((point, sequenceIndex) => {
          const { message, index } = point;
          const position = [message['position.latitude'], message['position.longitude']];
          const isMostRecent = index === lastLbsIndex;
          
          // Simplified approach to numbering:
          // Always start from 1 for historical points
          // Keep the main marker as 0
          // Don't skip points, but the most recent might overlap with main marker
          const sequenceNumber = sequenceIndex + 1; // Start from 1 for all historical points
          
          // Create marker for this point
          // Set z-index based on sequence number to ensure newer points appear on top
          // Higher z-index values appear on top, so we use 1000 - sequenceNumber
          // This ensures sequence 1 is on top of sequence 2, etc.
          const zIndexOffset = 1000 - sequenceNumber; // Highest numbers for newest points
          
          const pointMarker = L.marker(position, {
            icon: this.generateIcon(
              id, 
              this.markers[id].main.options.title, 
              this.markers[id].color, 
              message['position.source'], 
              isMostRecent,
              sequenceNumber
            ),
            draggable: false,
            messageIndex: index,
            zIndexOffset: zIndexOffset // This controls stacking order
          });
          
          // Add click event to show message details
          pointMarker.on('click', e => {
            console.log('Point marker clicked:', message);
            
            // Remove previous message point and info box
            if (this.map.messagePoint) { this.map.messagePoint.remove() }
            if (this.map.messageAccuracy) { this.map.messageAccuracy.remove(); this.map.messageAccuracy = null; }
            if (this.map.infoBox) { this.map.infoBox.remove(); this.map.infoBox = null; }
            
            // Create a pulse effect
            let pulseColor = message['position.source'].toLowerCase() === 'gps' ? '#000000' : '#FFA500';
            this.map.messagePoint = L.marker(position, {
              icon: L.divIcon({
                className: `my-round-marker-wrapper`,
                iconSize: new L.Point(10, 10),
                html: `<div class="my-round-marker" style="background-color: ${pulseColor};"></div>`
              })
            });
            this.map.messagePoint.addTo(this.map);
            
            // Show accuracy circle
            if (message['position.accuracy']) {
              const { accuracy, circleStyle } = this.getAccuracyParams(message);
              this.map.messageAccuracy = L.circle(position, accuracy, circleStyle);
              this.map.messageAccuracy.addTo(this.map);
            }
            
            // Create and show info box
            this.createInfoBox(message, position);
            
            // Select the message in the UI
            this.$store.commit(`messages/${id}/setSelected`, [index]);
          });
          
          // Add to the map and store in our collections
          pointMarker.addTo(this.map);
          this.markers[id].points['lbs'].push(pointMarker);
          
          // Create accuracy circle if needed
          if (message['position.accuracy']) {
            const { accuracy, circleStyle } = this.getAccuracyParams(message);
            const circle = L.circle(position, accuracy, circleStyle);
            circle.addTo(this.map);
            this.markers[id].accuracyCircles['lbs'].push(circle);
          }
        });
    },
    
    // Helper to find the last index in an array meeting a condition
    findLastIndex(array, predicate) {
      for (let i = array.length - 1; i >= 0; i--) {
        if (predicate(array[i])) {
          return i;
        }
      }
      return -1;
    },
    
    // Method to clear all points for a device
    clearAllPoints(id) {
      if (!this.markers[id] || !this.markers[id].points) {
        return;
      }
      
      // Remove GPS points
      if (this.markers[id].points.gps && this.markers[id].points.gps.length) {
        this.markers[id].points.gps.forEach(marker => {
          if (marker) marker.remove();
        });
        this.markers[id].points.gps = [];
      }
      
      // Remove LBS points
      if (this.markers[id].points.lbs && this.markers[id].points.lbs.length) {
        this.markers[id].points.lbs.forEach(marker => {
          if (marker) marker.remove();
        });
        this.markers[id].points.lbs = [];
      }
      
      // Remove GPS accuracy circles
      if (this.markers[id].accuracyCircles.gps && this.markers[id].accuracyCircles.gps.length) {
        this.markers[id].accuracyCircles.gps.forEach(circle => {
          if (circle) circle.remove();
        });
        this.markers[id].accuracyCircles.gps = [];
      }
      
      // Remove LBS accuracy circles
      if (this.markers[id].accuracyCircles.lbs && this.markers[id].accuracyCircles.lbs.length) {
        this.markers[id].accuracyCircles.lbs.forEach(circle => {
          if (circle) circle.remove();
        });
        this.markers[id].accuracyCircles.lbs = [];
      }
    },
    
    getLatLngArrByDevice (id) {
      if (!this.messages[id]) {
        return []
      }
      return this.messages[id].reduce((acc, message) => {
        // The messages array should already be filtered for LBS points,
        // but we double-check here to ensure tracks are consistent
        if (!this.params.needShowLBSPoints && 
            message['position.source'] && 
            message['position.source'].toLowerCase() === 'lbs') {
          return acc;
        }
        acc.push([message['position.latitude'], message['position.longitude']])
        return acc
      }, [])
    },
    onResize () {
      if (this.map) {
        this.map.invalidateSize()
      }
    },
    removeMarker (id) {
      if (this.markers[id]) {
        this.removeFlags(id)
        
        // Remove main marker
        if (this.markers[id].main && this.markers[id].main instanceof L.Marker) {
          this.map.removeLayer(this.markers[id].accuracy)
          this.markers[id].main.remove()
        }
        
        // Remove all points
        this.clearAllPoints(id)
        
        // Remove tracks
        if (this.tracks[id]) {
          if (this.tracks[id].tail && this.tracks[id].tail instanceof L.Polyline) {
            this.tracks[id].tail.remove()
          }
          if (this.tracks[id].overview && this.tracks[id].overview instanceof L.Polyline) {
            this.tracks[id].overview.remove()
          }
          if (this.tracks[id] instanceof L.Polyline) {
            this.tracks[id].remove()
          }
        }
      }
      Vue.delete(this.markers, id)
      Vue.delete(this.tracks, id)
    },
    /**
     * Fly to a device with smooth animation
     * Uses auto-zoom for multiple points or flyTo for single points
     * 
     * This enhances the user experience by:
     * 1. Showing all points for a device with appropriate padding when multiple points exist
     * 2. Zooming to a comfortable level for single points
     * 3. Using smooth animations for transitions
     * 
     * @param {number|string} id - The device ID to fly to
     */
    flyToDevice (id) {
      // If we have multiple messages for the device, use auto-zoom to show all points
      if (this.messages[id] && this.messages[id].length > 1) {
        // Filter points to only include the selected device
        const allPoints = [];
        const devicePoints = this.messages[id].filter(msg => {
          // Only include points with valid coordinates
          if (!msg['position.latitude'] || !msg['position.longitude']) return false;
          
          // Skip LBS points if the toggle is off
          if (!this.params.needShowLBSPoints && 
              msg['position.source'] && 
              msg['position.source'].toLowerCase() === 'lbs') {
            return false;
          }
          
          return true;
        }).map(msg => [msg['position.latitude'], msg['position.longitude']]);
        
        allPoints.push(...devicePoints);
        
        if (allPoints.length) {
          // Create a bounds object with generous padding for better view
          const bounds = L.latLngBounds(allPoints);
          this.map.flyToBounds(bounds, {
            padding: [
              120,  // Top padding (px) - more space for date selector
              200   // Left/right/bottom padding (px) - for message boxes and controls
            ],
            maxZoom: 18,      // Don't zoom in too far
            animate: true     // Smooth animation
          });
          return;
        }
      }
      
      // Fall back to the original single-point logic if we don't have multiple points
      const devicesById = this.activeDevices.filter(device => device.id === id),
        currentDevice = devicesById.length ? devicesById[0] : null
      let currentPos = currentDevice && []
      if (this.messages[id] && this.messages[id].length) {
        currentPos = [this.messages[id][this.messages[id].length - 1]['position.latitude'], this.messages[id][this.messages[id].length - 1]['position.longitude']]
      }
      if (currentPos && currentPos.length) {
        this.flyToWithHideTracks(currentPos, this.flyToZoom)
      } else {
        this.$q.notify({
          message: 'No Position!',
          color: 'warning',
          timeout: this.params.needShowMessages ? 500 : 2000
        })
      }
    },
    /**
     * Center the map on a device
     * Without animation, unlike flyToDevice
     * 
     * This method:
     * 1. Auto-zooms to fit all points for a device when no specific zoom level is provided
     * 2. Uses the provided zoom level if specified (for manual control)
     * 3. Works immediately without animations for responsive UI
     * 
     * @param {number|string} id - The device ID to center on
     * @param {number} zoom - Optional zoom level to use
     */
    centerOnDevice (id, zoom) {
      // If we have multiple messages for the device, use auto-zoom to show all points
      if (!zoom && this.messages[id] && this.messages[id].length > 1) {
        // Filter points to only include the selected device
        const allPoints = [];
        const devicePoints = this.messages[id].filter(msg => {
          // Only include points with valid coordinates
          if (!msg['position.latitude'] || !msg['position.longitude']) return false;
          
          // Skip LBS points if the toggle is off
          if (!this.params.needShowLBSPoints && 
              msg['position.source'] && 
              msg['position.source'].toLowerCase() === 'lbs') {
            return false;
          }
          
          return true;
        }).map(msg => [msg['position.latitude'], msg['position.longitude']]);
        
        allPoints.push(...devicePoints);
        
        if (allPoints.length) {
          // Create a bounds object with padding for better view
          const bounds = L.latLngBounds(allPoints);
          this.map.fitBounds(bounds, {
            padding: [50, 50], // Padding in pixels
            maxZoom: 18,       // Don't zoom in too far
            animate: false     // No animation for center
          });
          return;
        }
      }
      
      // Fall back to the original single-point logic if we have a specific zoom or single point
      const devicesById = this.activeDevices.filter(device => device.id === id),
        currentDevice = devicesById.length ? devicesById[0] : null
      let currentPos = currentDevice && []
      if (this.messages[id] && this.messages[id].length) {
        currentPos = [this.messages[id][this.messages[id].length - 1]['position.latitude'], this.messages[id][this.messages[id].length - 1]['position.longitude']]
      }
      if (currentPos.length) {
        // Use a moderate zoom level by default (16 instead of 18)
        // This gives more context around the point and prevents UI elements from obscuring it
        this.map.setView(currentPos, zoom ? zoom : 16, { animation: false })
      } else {
        this.$q.notify({
          message: 'No Position!',
          color: 'warning',
          timeout: this.params.needShowMessages ? 500 : 2000
        })
      }
    },
    generateFlag (props) {
      let { id, status } = props || {}
      let color = id ? this.devicesColors[id] : '#e53935',
        icon = 'map-marker-star-outline'
      if (status === 'start') {
        color = colors.getBrand('primary')
        icon = 'map-marker-outline'
      } else if (status === 'stop') {
        color = colors.getBrand('positive')
        icon = 'map-marker-check'
      }
      return L.divIcon({
        className: `my-flag-icon flag-${status}-${id}`,
        iconSize: new L.Point(35, 35),
        html: `<i aria-hidden="true" style="color: ${color};" class="my-flag-icon__inner mdi mdi-${icon}"></i>`
      })
    },
    addFlags (id) {
      if (!this.markers[id]) {
        return false
      }
      if (!this.markers[id].flags) {
        this.markers[id].flags = {
          start: {},
          stop: {}
        }
      }
      if (this.messages[id].length) {
        const startPosition = [this.messages[id][0]['position.latitude'], this.messages[id][0]['position.longitude']],
          stopPosition = [this.messages[id][this.messages[id].length - 1]['position.latitude'], this.messages[id][this.messages[id].length - 1]['position.longitude']]
        this.markers[id].flags.start = L.marker(startPosition, {
          icon: this.generateFlag({ id, status: 'start' })
        })
        this.markers[id].flags.start.addTo(this.map)
        this.markers[id].flags.stop = L.marker(stopPosition, {
          icon: this.generateFlag({ id, status: 'stop' })
        })
        const needStopFlag = this.$store.state.messages[id].to <= Date.now()
        needStopFlag && this.markers[id].flags.stop.addTo(this.map)
      }
    },
    removeFlags (id) {
      if (!this.markers[id] || !this.markers[id].flags || !(this.markers[id].flags.start instanceof L.Marker) || !(this.markers[id].flags.stop instanceof L.Marker)) {
        return false
      }
      this.markers[id].flags.start.remove()
      this.markers[id].flags.stop.remove()
      this.markers[id].flags = undefined
    },
    async getDeviceData (id) {
      if (id) {
        if (this.$store.state.messages[id].realtimeEnabled) {
          await this.$store.dispatch(`messages/${id}/unsubscribePooling`)
        }
        this.$store.commit(`messages/${id}/clearMessages`)
        const from = this.date[0]
        const to = this.date[1]
        this.$store.commit(`messages/${id}/setFrom`, from)
        this.$store.commit(`messages/${id}/setTo`, to)
        await this.$store.dispatch(`messages/${id}/get`)
        if (to > Date.now()) {
          const render = await this.$store.dispatch(`messages/${id}/pollingGet`)
          render()
        }
        this.addFlags(id)
        if (!this.$store.state.messages[id].messages.length) {
          try {
            /* try to init device by telemetry */
            this.devicesState[id].telemetryAccess = true
            await this.$store.dispatch('getInitDataByDeviceId', [id, this.params.needShowInvalidPositionMessages])
          } catch (err) {
            if (err.response && err.response.status && err.response.status === 403) {
              this.devicesState[id].telemetryAccess = false
            }
          }
        }
        /* device initialization is completed - device is initialized either from messages or from telemetry */
        this.devicesState[id].initStatus = true
        /* check if device doesn't have access neither to messages, nor to telemetry, and mark it with property */
        if (this.devicesState[id].messagesAccess === false && this.devicesState[id].telemetryAccess === false) {
          /* find device and mark it with a special propery */
          const device = this.activeDevices.filter(device => device.id === id)[0]
          Object.defineProperty(device, 'x-flespi-no-access', {
            value: true,
            enumerable: false
          })
        }
      }
    },
    async initDevice (id) {
      this.$q.loading.show()
      if (id) {
        this.$store.commit(`messages/${id}/setActive`, id)
        await this.$store.dispatch(`messages/${id}/getCols`, { actions: true, etc: true })
        await this.getDeviceData(id)
      }
      Vue.connector.socket.on('offline', () => { this.$store.commit(`messages/${id}/setOffline`) })
      Vue.connector.socket.on('connect', () => {
        if (this.$store.state.messages[id].offline) {
          this.$store.commit(`messages/${id}/setReconnected`)
          this.$store.dispatch(`messages/${id}/getMissedMessages`)
        }
      })
      if (id === this.selectedDeviceId && this.devicesState[id].initStatus === true) {
        this.telemetryDeviceId = parseInt(id)
        this.$emit('update-telemetry-device-id', this.telemetryDeviceId)
        this.centerOnDevice(id)
      }
      this.$q.loading.hide()
    },
    viewOnMapHandler (content) {
      if (content['position.latitude'] && content['position.longitude']) {
        const position = [content['position.latitude'], content['position.longitude']],
          currentZoom = this.map.getZoom(),
          positionSource = content['position.source'] || null
        
        // Remove existing elements
        if (this.map.messagePoint) { this.map.messagePoint.remove() }
        if (this.map.infoBox) { this.map.infoBox.remove(); this.map.infoBox = null; }
        
        // Set color based on position source
        let pulseColor = '#FF5252' // Default red color
        if (positionSource) {
          if (positionSource.toLowerCase() === 'gps') {
            pulseColor = '#000000' // Black for GPS
          } else if (positionSource.toLowerCase() === 'lbs') {
            pulseColor = '#FFA500' // Orange for LBS
          }
        }
        
        this.map.messagePoint = L.marker(position, {
          icon: L.divIcon({
            className: `my-round-marker-wrapper`,
            iconSize: new L.Point(10, 10),
            html: `<div class="my-round-marker" style="background-color: ${pulseColor};"></div>`
          })
        })
        this.map.messagePoint.addTo(this.map)
        
        // Create an accuracy circle for this point if it has accuracy data
        if (content['position.accuracy'] && !this.map.messageAccuracy) {
          const { accuracy, circleStyle } = this.getAccuracyParams(content)
          this.map.messageAccuracy = L.circle(position, accuracy, circleStyle)
          this.map.messageAccuracy.addTo(this.map)
        } else if (this.map.messageAccuracy) {
          // Update existing accuracy circle
          const { accuracy, circleStyle } = this.getAccuracyParams(content)
          this.map.messageAccuracy.setRadius(accuracy)
          this.map.messageAccuracy.setLatLng(position)
          this.map.messageAccuracy.setStyle(circleStyle)
        }
        
        // Create and show info box
        this.createInfoBox(content, position);
        
        this.map.setView(position, currentZoom > 18 ? currentZoom : 18, { animation: false })
      } else {
        this.$q.notify({
          message: 'No position',
          color: 'warning',
          position: 'bottom-left',
          icon: 'mdi-alert-outline'
        })
      }
    },
    playProcess (data, type) {
      const mode = this.player.mode === 'data' ? 0 : 1
      switch (type) {
        case 'value': {
          mode ? this.playerTimeValue(data) : this.playerDataValue(data)
          break
        }
        case 'play': {
          if (this.player.status === 'play') { return }
          mode ? this.playerTimePlay(data) : this.playerDataPlay(data)
          break
        }
        case 'stop': {
          if (this.player.status === 'stop') { return }
          mode ? this.playerTimeStop(data) : this.playerDataStop(data)
          break
        }
        case 'pause': {
          if (this.player.status === 'pause') { return }
          mode ? this.playerTimePause(data) : this.playerDataPause(data)
          break
        }
      }
    },
    playerTimeValue ({ id, messagesIndexes }) {
      if (!this.messages[id] || !messagesIndexes || this.player.status !== 'play') { return false }
      let renderDuration = 0,
        lastMessageIndexWithPosition = null
      const endIndex = messagesIndexes[messagesIndexes.length - 1],
        startIndex = 0,
        tailMessages = this.messages[id].slice(startIndex, endIndex + 1),
        tail = tailMessages.reduce((tail, message, index) => {
          if (typeof message['position.latitude'] === 'number' && typeof message['position.longitude'] === 'number') {
            // Skip LBS points if the toggle is off
            if (!this.params.needShowLBSPoints && 
                message['position.source'] && 
                message['position.source'].toLowerCase() === 'lbs') {
              return tail;
            }
            lastMessageIndexWithPosition = index
            tail.push([message['position.latitude'], message['position.longitude']])
          }
          return tail
        }, [])
      messagesIndexes.forEach((messageIndex) => {
        if (this.markers[id] && this.markers[id] instanceof L.Marker) {
          const message = this.messages[id][messageIndex]
          const havePosition = message && 
                              typeof message['position.latitude'] === 'number' && 
                              typeof message['position.longitude'] === 'number'
          
          // Skip LBS points if the toggle is off
          if (!this.params.needShowLBSPoints && 
              message && message['position.source'] && 
              message['position.source'].toLowerCase() === 'lbs') {
            // We skip updating the marker for LBS points when they're filtered
            this.player.currentMsgIndex = messageIndex
            return;
          }
          
          this.player.currentMsgIndex = messageIndex
          if (havePosition) {
            const pos = [message['position.latitude'], message['position.longitude']]
            if (this.player.status === 'play' && messagesIndexes[0] !== 0) {
              let duration = ((1000 / this.player.speed) / messagesIndexes.length)
              if (messageIndex !== 0) {
                const prevTimestamp = this.messages[id][messageIndex - 1].timestamp,
                  currentTimestamp = message.timestamp,
                  durationInSeconds = currentTimestamp - prevTimestamp
                duration = ((durationInSeconds * 1000) / this.player.speed)
                renderDuration = durationInSeconds
              }
              duration = duration - 50
              if (duration) {
                this.markers[id].slideTo(pos, { duration: duration })
              } else {
                this.markers[id].setLatLng(pos).update()
              }
              this.updateMarkerDirection(id, message['position.direction'])
              
              // Update marker with position source information
              this.updateMarker(id, pos, message['position.direction'], message)
            } else {
              this.markers[id].setLatLng(pos).update()
              this.updateMarker(id, pos, message['position.direction'], message)
            }
            
            // Get accuracy parameters with the new position source
            const { accuracy, circleStyle } = this.getAccuracyParams(message)
            this.markers[id].accuracy.setRadius(accuracy)
            this.markers[id].accuracy.setLatLng(pos)
            
            // Update accuracy circle style based on position source
            this.markers[id].accuracy.setStyle(circleStyle)
          } else {
            const message = this.messages[id][lastMessageIndexWithPosition]
            const pos = tail[tail.length - 1]
            this.markers[id].setLatLng(pos).update()
            this.updateMarker(id, pos, message['position.direction'], message)
            
            // Get accuracy parameters with the new position source
            const { accuracy, circleStyle } = this.getAccuracyParams(message)
            this.markers[id].accuracy.setRadius(accuracy)
            this.markers[id].accuracy.setLatLng(pos)
            
            // Update accuracy circle style based on position source
            this.markers[id].accuracy.setStyle(circleStyle)
          }
        }
      })
      /* tail render logic */
      if (this.tracks[id] && this.tracks[id] instanceof L.Polyline && tail.length) {
        if (!this.tracks[id].tail || !(this.tracks[id].tail instanceof L.Polyline)) {
          this.tracks[id].tail = L.polyline(tail, this.tracks[id].options)
          this.tracks[id].tail.addTo(this.map)
          this.tracks[id].tail.on('click', (e) => {
            console.log('Track tail clicked for device:', id);
            this.showMessageByTrackClick(e, id, this.tracks[id].tail);
          })
          return true
        }
        if (this.player.tailInterval) { clearTimeout(this.player.tailInterval) }
        this.player.tailInterval = setTimeout(() => { this.tracks[id].tail && this.tracks[id].tail.setLatLngs(tail) }, ((renderDuration * 700) / this.player.speed))
      }
    },
    playerTimePlay ({ id }) {
      if (this.tracks[id] && this.tracks[id] instanceof L.Polyline) {
        this.tracks[id].remove()
        this.player.status = 'play'
      }
    },
    playerTimeStop ({ id }) {
      if (this.tracks[id] && this.tracks[id] instanceof L.Polyline) {
        if (this.tracks[id].tail) {
          this.tracks[id].tail.remove()
          delete this.tracks[id].tail
        }
        const realtimeEnabled = this.$store.state.messages[id].realtimeEnabled
        const msgIndex = realtimeEnabled ? this.messages[id].length - 1 : 0
        const message = this.messages[id][msgIndex]
        this.$nextTick(() => { this.player.currentMsgIndex = msgIndex ? null : 0 })
        this.player.status = 'stop'
        this.tracks[id].addTo(this.map)
        const lastPos = [message['position.latitude'], message['position.longitude']]
        this.updateMarker(id, lastPos, message['position.direction'])
      }
    },
    playerTimePause ({ id }) {
      this.player.status = 'pause'
    },
    playerDataValue ({ id }) {},
    playerDataPlay ({ id }) {
      if (this.player.status === 'pause') {
        this.tracks[id].overview.snakeUnpause()
        this.player.status = 'play'
        return
      }
      this.player.status = 'play'
      this.tracks[id].remove()
      
      // Filter messages to exclude LBS points if the toggle is off
      const filteredMessages = this.params.needShowLBSPoints 
        ? this.messages[id] 
        : this.messages[id].filter(message => 
            !message['position.source'] || 
            message['position.source'].toLowerCase() !== 'lbs'
          );
      
      const latlngs = filteredMessages.map((message, index) => ({
        lat: message['position.latitude'],
        lng: message['position.longitude'],
        dir: message['position.direction'],
        index
      }))
      
      if (latlngs.length < 2) {
        this.tracks[id].addTo(this.map)
        this.player.status = 'stop'
        this.player.currentMsgIndex = null
        return
      }
      const line = L.polyline(latlngs, { snakingSpeed: 20 * this.player.speed, color: this.tracks[id].options.color })
      this.tracks[id].overview = line
      this.tracks[id].overview.on('click', (e) => {
        console.log('Track overview clicked for device:', id);
        this.showMessageByTrackClick(e, id, this.tracks[id].overview);
      })
      line.addTo(this.map).snakeIn()
      line.on('snake', () => {
        const points = line.getLatLngs()
        const point = points.slice(-1)[0]
        const lastPos = point.slice(-1)[0]
        const message = latlngs[points[0].length - 1]
        this.updateMarker(id, lastPos, message.dir)
        if (this.player.currentMsgIndex !== message.index) {
          this.player.currentMsgIndex = message.index
        }
      })
      line.on('snakeInEnd', () => {
        this.playerDataStop({ id })
      })
    },
    playerDataStop ({ id }) {
      this.player.status = 'stop'
      if (this.tracks[id].overview) {
        this.tracks[id].overview.remove()
        delete this.tracks[id].overview
      }
      if (this.tracks[id] && this.tracks[id] instanceof L.Polyline) {
        this.tracks[id].addTo(this.map)
        this.tracks[id].on('click', (e) => {
          console.log('Track clicked for device (playerdatastop):', id);
          this.showMessageByTrackClick(e, id, this.tracks[id]);
        })
      }
      const message = this.messages[id].slice(-1)[0]
      this.player.currentMsgIndex = null
      if (message) {
        const lastPos = [message['position.latitude'], message['position.longitude']]
        this.updateMarker(id, lastPos, message['position.direction'])
      }
    },
    playerDataPause ({ id }) {
      if (this.player.status === 'stop') { return }
      this.player.status = 'pause'
      this.tracks[id].overview.snakePause()
    },
    playerSpeedChangeHandler ({ speed, id }) {
      this.player.speed = speed
      if (this.player.mode === 'data' && this.player.status !== 'stop') {
        this.tracks[id].overview.setStyle({ snakingSpeed: 20 * speed })
      }
    },
    playerModeChange ({ id, mode }) {
      if (this.player.status !== 'stop') {
        if (mode === 'data') {
          this.playerTimeStop({ id })
        } else {
          this.playerDataStop({ id })
        }
      }
      this.player.mode = mode
    },
    updateColorHandler ({ id, color }) {
      this.$emit('update-color', id, color)
    },
    updateDeviceColorOnMap (id, color) {
      if (!this.tracks[id] || !(this.tracks[id] instanceof L.Polyline) ||
          !this.markers[id] || !this.markers[id].main || !(this.markers[id].main instanceof L.Marker)) {
        return false
      }
      
      // Update track colors
      this.tracks[id].setStyle({ color })
      this.tracks[id].tail && this.tracks[id].tail.setStyle({ color })
      this.tracks[id].overview && this.tracks[id].overview.setStyle({ color })
      
      // Update main marker color
      this.markers[id].color = color
      this.markers[id].main.color = color
      
      const positionSource = this.markers[id].main.positionSource;
      const isMostRecent = this.markers[id].main.options.icon.options.html.includes('stroke-width="3"');
      
      this.markers[id].main.setIcon(this.generateIcon(
        id, 
        this.markers[id].main.options.title, 
        color,
        positionSource,
        isMostRecent,
        0 // Use "0" for current position
      ))
      
      if (this.messages[id][this.messages[id].length - 1]['position.direction']) {
        /* restore marker's direction, if known */
        this.updateMarkerDirection(id, this.messages[id][this.messages[id].length - 1]['position.direction'])
      }
      
      // Reinitialize all points with the new color
      this.initAllPoints(id);
    },
    registerModule (id) {
      this.devicesState[id] = { messagesAccess: true }
      this.$store.registerModule(
        ['messages', id],
        devicesMessagesModule({
          Vue,
          LocalStorage: this.$q.localStorage,
          name: { name: 'messages', lsNamespace: `${this.$store.state.storeName}.cols` },
          errorHandler: (err) => {
            if (err.response && err.response.status && err.response.status === 403) {
              this.devicesState[id].messagesAccess = false
            } else {
              this.$store.commit('reqFailed', err)
            }
          }
        }))
    },
    showMessageByTrackClick (e, id, track) {
      e.originalEvent.view.L.DomEvent.stopPropagation(e)
      const messages = this.messages[id]
      const position = L.GeometryUtil.closest(this.map, track, e.latlng)
      const indexes = messages.reduce((res, message, index) => {
        const lat = message['position.latitude']
        const lng = message['position.longitude']
        const nextMessage = messages[index + 1]
        if (!nextMessage) { return res }
        const nextLat = nextMessage['position.latitude']
        const nextLng = nextMessage['position.longitude']
        const isPosBetweenLat = (lat >= position.lat && nextLat <= position.lat) || (lat <= position.lat && nextLat >= position.lat)
        const isPosBetweenLng = (lng >= position.lng && nextLng <= position.lng) || (lng <= position.lng && nextLng >= position.lng)
        if (isPosBetweenLat && isPosBetweenLng) {
          const distance = L.GeometryUtil.distance(this.map, position, {lat, lng})
          const nextDistance = L.GeometryUtil.distance(this.map, position, {lat: nextLat, lng: nextLng})
          const closestMessageIndex = distance > nextDistance ? index + 1 : index
          res.push(closestMessageIndex)
        }
        return res
      }, [])
      
      const messageIndex = indexes.slice(-1)[0]
      const lastMessage = messages[messageIndex] || {}
      
      // Create a pulsing point for the selected message
      if (lastMessage['position.latitude'] && lastMessage['position.longitude']) {
        const pulsePos = [lastMessage['position.latitude'], lastMessage['position.longitude']]
        const positionSource = lastMessage['position.source'] || null
        
        // Remove existing pulse point and info box if any
        if (this.map.messagePoint) { this.map.messagePoint.remove() }
        if (this.map.infoBox) { this.map.infoBox.remove(); this.map.infoBox = null; }
        
        // Create a pulse marker with color based on position source
        let pulseColor = '#FF5252' // Default red color
        if (positionSource) {
          if (positionSource.toLowerCase() === 'gps') {
            pulseColor = '#000000' // Black for GPS
          } else if (positionSource.toLowerCase() === 'lbs') {
            pulseColor = '#FFA500' // Orange for LBS
          }
        }
        
        this.map.messagePoint = L.marker(pulsePos, {
          icon: L.divIcon({
            className: `my-round-marker-wrapper`,
            iconSize: new L.Point(10, 10),
            html: `<div class="my-round-marker" style="background-color: ${pulseColor};"></div>`
          })
        })
        this.map.messagePoint.addTo(this.map)
        
        // Create and show info box
        this.createInfoBox(lastMessage, pulsePos);
      }
      
      this.viewOnMapHandler(lastMessage)
      this.$store.commit(`messages/${id}/setSelected`, indexes)
    },
    mapClickHandler (e) {
      if (this.map.messagePoint) { this.map.messagePoint.remove() }
      if (this.map.messageAccuracy) { this.map.messageAccuracy.remove(); this.map.messageAccuracy = null; }
      if (this.map.infoBox) { this.map.infoBox.remove(); this.map.infoBox = null; }
      this.activeDevicesID.forEach((id) => {
        this.$store.commit(`messages/${id}/clearSelected`)
      })
    },

    updateOrInitDevice (id) {
      /* this method is triggered by watch messages - "messages" object in the state has changed  */

      if (!this.messages[id] || !this.messages[id].length) {
        /* device has not messages, this my happen because initialization is not yet completed in getDeviceData */
        if (!this.markers[id]) {
          /* however we already need to create marker for the device, if not yet created */
          /* this is needed for Queue component to know the current color of the device for color-view div (color picker button) */
          this.markers[id] = {}
          this.markers[id].id = id
          this.markers[id].color = this.devicesColors[id]
          this.tracks[id] = {}
        }
        return false
      }

      /* now device has messages, either normal flespi messages, or synthetic 'x-flespi-inited-by-telemetry' message */

      if (!this.markers[id].main || !(this.markers[id].main instanceof L.Marker) || !(this.tracks[id] instanceof L.Polyline)) {
        /* the marker and track of the device are not yet initialized as leaflet instances */
        /* we've received messages and now it's time to init the marker and attach it to the map */
        const name = this.activeDevices.filter(device => device.id === parseInt(id))[0].name || `#${id}`,
          position = [this.messages[id][this.messages[id].length - 1]['position.latitude'], this.messages[id][this.messages[id].length - 1]['position.longitude']]
        this.initMarker(id, name, position)
        /* init track */
        this.tracks[id] = L.polyline(this.getLatLngArrByDevice(id), { weight: 4, color: this.markers[id] ? this.markers[id].color : this.devicesColors[id] }).addTo(this.map)
        this.tracks[id].on('click', (e) => {
          console.log('Track clicked for device (init):', id);
          this.showMessageByTrackClick(e, id, this.tracks[id]);
        })

        if (Number.parseInt(id) === this.selected) { // here typeof id is string
          if (this.messages[id].length > 1) {
            /* device has a bunch of messages - initially show the whole track with padding */
            // Auto-zoom to show all points with a buffer around the edges
            this.autoZoomToFitPoints();
          } else {
            /* device has only one message - initially show only device in comfortable zoom */
            // For a single point, use a fixed zoom level that's zoomed out a bit to provide buffer
            // Reduced from 16 to 15 for more context around the point
            this.map.setView(position, 15, { animation: false })
          }
        }
      } else {
        // We have existing markers but the messages changed, so refresh all points
        this.initAllPoints(id);
      }

      /* now update device on map according to the newly received message */
      if (!this.devicesState[id].messagesAccess) {
        /* this device has no access to messages, nothing more to do here for this device */
        return false
      }

      const currentArrPos = this.getLatLngArrByDevice(id)
      if (this.isSelectedDeviceFollowed) {
        const markerWatchedPos = this.selectedDeviceId && this.selectedDeviceId == id && this.markers[this.selectedDeviceId] && this.markers[this.selectedDeviceId].main instanceof L.Marker ? this.markers[this.selectedDeviceId].main.getLatLng() : {},
          isWatchedPosChanged = this.selectedDeviceId && this.messages[this.selectedDeviceId] && this.messages[this.selectedDeviceId].length &&
            markerWatchedPos.lat && markerWatchedPos.lat !== this.messages[this.selectedDeviceId][this.messages[this.selectedDeviceId].length - 1]['position.latitude'] &&
            markerWatchedPos.lng && markerWatchedPos.lng !== this.messages[this.selectedDeviceId][this.messages[this.selectedDeviceId].length - 1]['position.longitude']
        if (isWatchedPosChanged) {
          const position = currentArrPos[currentArrPos.length - 1]
          position && this.centerOnDevice(this.selectedDeviceId, this.map.getZoom())
        }
      }
      /* if positions are empty clear marker and line */
      if (!currentArrPos.length) {
        this.removeFlags(id)
        if (this.tracks[id].tail && this.tracks[id].tail instanceof L.Polyline) {
          this.tracks[id].tail.remove()
        }
        if (this.tracks[id].overview && this.tracks[id].overview instanceof L.Polyline) {
          this.tracks[id].overview.remove()
        }
        if (this.markers[id].accuracy) {
          this.map.removeLayer(this.markers[id].accuracy)
        }
        // Clear all points
        this.clearAllPoints(id)
        
        if (this.tracks[id] instanceof L.Polyline) {
          this.map.removeLayer(this.tracks[id])
        }
        
        if (this.markers[id].main instanceof L.Marker) {
          this.map.removeLayer(this.markers[id].main)
        }
        
        this.tracks[id] = {}
        const prevColor = this.markers[id].color || undefined;
        this.markers[id] = {
          color: prevColor,
          id: id,
          points: { gps: [], lbs: [] },
          accuracyCircles: { gps: [], lbs: [] }
        }
      } else {
        /* update marker and track with newly recevied position */
        const lastMessage = this.messages[id][this.messages[id].length - 1]
        const pos = currentArrPos[currentArrPos.length - 1]
        
        // Update main marker position and information
        this.markers[id].main.setLatLng(pos).update()
        this.updateMarker(id, pos, lastMessage['position.direction'], lastMessage)
        
        // Get accuracy parameters with the new position source
        const { accuracy, circleStyle } = this.getAccuracyParams(lastMessage)
        this.markers[id].accuracy.setRadius(accuracy)
        this.markers[id].accuracy.setLatLng(pos)
        
        // Update accuracy circle style based on position source
        this.markers[id].accuracy.setStyle(circleStyle)
        
        this.markers[id].main.setOpacity(1)
        this.tracks[id].setLatLngs(currentArrPos)
      }
    },
    updateStateByMessages (messages) {
      if (this.player.status === 'play' || this.player.status === 'pause') { return false }
      const keyArr = Object.keys(messages),
        oldKeyArr = Object.keys(this.markers)
      if (!keyArr.length) {
        Object.keys(this.markers).forEach(id => {
          this.removeMarker(id)
        })
        return false
      }
      if (keyArr.length < oldKeyArr.length) {
        const removeDeviceId = oldKeyArr.filter(key => !keyArr.includes(key))[0]
        this.removeMarker(removeDeviceId)
        return false
      }
      
      // Update all devices - this will also initialize all points
      keyArr.forEach(id => this.updateOrInitDevice(id));
      
      // Auto-zoom to fit all visible points with padding
      // Only do this if we're not in player mode and not following a specific device
      // This ensures the map shows all points with a reasonable buffer when data updates
      if (!this.isSelectedDeviceFollowed) {
        setTimeout(() => this.autoZoomToFitPoints(), 100); // Small delay to ensure points are rendered
      }
    },
    updateStateByTelemetry (telemetry) {
      /* this method is triggered by watch telemetry: telemetry has updated */
      /* update device on map, if this device has no messages and therefore should be drawn on map by telemetry */
      if (!Object.keys(telemetry.telemetry).length) {
        /* nothing to do if we have no telemetry parameters yet */
        return false
      }
      const id = telemetry.deviceId
      if (!this.devicesState[id].telemetryAccess) {
        /* this device either has access to messages or has no access to telemetry, it will be drawn on map by messages (if any), nothing to do with it here */
        return false
      }
      if (!this.messages || !this.messages[id] || !this.messages[id][0]) {
        /* messages are not here, either initialization is not yet completed or this device has never sent a message to flespi */
        /* each device must have at least one message, either normal or syntethic 'x-flespi-inited-by-telemetry' one */
        return false
      }
      if (this.messages[id].lenth > 1 || !this.messages[id][0]['x-flespi-inited-by-telemetry']) {
        /* this device has normal messages, it will be drawn on map by messages, nothing to do here */
        /* actually, this should never happen */
        return false
      }

      /* retrieve position from telemetry and validate it */
      const lat = Number.parseFloat(telemetry.telemetry['position.latitude'].value)
      const latTs = Number.parseFloat(telemetry.telemetry['position.latitude'].ts)
      const lon = Number.parseFloat(telemetry.telemetry['position.longitude'].value)
      const lonTs = Number.parseFloat(telemetry.telemetry['position.longitude'].ts)
      if (Math.round(latTs * 1000) !== Math.round(lonTs * 1000)) {
        /* check that lan and lon come correspond to the same point of time */
        /* server should update them cosistently, but still */
        console.error("Wrong telemetry")
        return false
      }

      if (!this.params.needShowInvalidPositionMessages) {
        /* check if position.valid=false parameter has the same timestamp as the latest position, and skip it */
        if (telemetry.telemetry['position.valid'] && telemetry.telemetry['position.valid'].value === false &&
            (Math.abs(Number.parseFloat(telemetry.telemetry['position.valid'].ts - latTs) < 0.1))) {
          return false
        }
      }

      /* we recevied new position from telemetry */
      /* update syntethic 'x-flespi-inited-by-telemetry' message with position from the new telemetry */
      this.messages[id][0]['position.latitude'] = lat
      this.messages[id][0]['position.longitude'] = lon
      this.messages[id][0]['timestamp'] = latTs

      /* add other position parameters if they have the same simestamp as lat&lon, otherwise - clean them up */
      const positionParams =      [ 'direction', 'speed',  'altitude', 'valid',    'satellites', 'hdop',   'pdop'   ]
      const positionParamsType =  [ 'number',    'number', 'number',   'boolean',  'number',     'number', 'number' ]

      for (let i = 0; i < positionParams.length; i++) {
        const paramName = 'position.' + positionParams[i]
        const paramType = positionParamsType[i]

        if (telemetry.telemetry[paramName] && (Math.abs(Number.parseFloat(telemetry.telemetry[paramName].ts) - latTs) < 0.1)) {
          switch(paramType) {
            case 'number': // why numbers are received as strings ?? : {"position.direction":{"value":"168","ts":"1724842304"}
              this.messages[id][0][paramName] = Number.parseFloat(telemetry.telemetry[paramName].value)
              break
            default:
              this.messages[id][0][paramName] = telemetry.telemetry[paramName].value
              break
          }
        } else {
          delete this.messages[id][0][paramName]
        }
      }

      /* store the last telemetry position to draw the tail on the map, up to 50 points */
      if (!this.devicesState[id].telemetryTail) {
        this.devicesState[id].telemetryTail = []
      } else if (this.devicesState[id].telemetryTail.length > 50) {
        this.devicesState[id].telemetryTail.shift()
      }
      this.devicesState[id].telemetryTail.push([lat, lon])

      /* update marker and track on the map */
      if (this.markers[id] instanceof L.Marker) {
        const direction = (telemetry.telemetry['position.direction'] && (Math.abs(Number.parseFloat(telemetry.telemetry['position.direction'].ts)) - latTs) < 0.1) ?
                          Number.parseInt(telemetry.telemetry['position.direction'].value) : 0
        this.updateMarkerDirection(id, direction)
        this.markers[id].setLatLng([lat, lon]).update()
      }
      if (this.tracks[id] instanceof L.Polyline) {
        this.tracks[id].setLatLngs(this.devicesState[id].telemetryTail)
      }
      if (this.isSelectedDeviceFollowed) {
        this.centerOnDevice(this.selectedDeviceId, this.map.getZoom())
      }
    }
  },
  watch: {
    messages: {
      deep: true,
      handler (messages) {
        this.debouncedUpdateStateByMessages(messages)
      }
    },
    telemetry: {
      deep: true,
      handler (telemetry) {
        if (this.devicesState[telemetry.deviceId] && this.devicesState[telemetry.deviceId].messagesAccess) {
          /* this device is positioned by messages, no need to draw its position by telemetry */
          return false
        }
        this.debouncedUpdateStateByTelemetry(telemetry)
      }
    },
    activeDevices (newVal) {
      const activeDevicesID = newVal.map((device) => device.id)
      const currentDevicesID = Object.keys(this.messages).map(id => parseInt(id)),
        modifyType = currentDevicesID.length > activeDevicesID.length ? 'remove' : 'add'
      activeDevicesID.forEach((id) => {
        if (!this.$store.state.messages[id]) {
          this.registerModule(id)
          this.$store.commit(`messages/${id}/setSortBy`, 'timestamp')
          this.$store.commit(`messages/${id}/setReverse`, true)
          this.$store.commit(`messages/${id}/setLimit`, 0)
        }
      })
      this.activeDevicesID = activeDevicesID
      switch (modifyType) {
        case 'remove': {
          const removedDevicesID = currentDevicesID.filter(id => !activeDevicesID.includes(id))
          if (removedDevicesID.length === 1 && removedDevicesID[0]) {
            this.$store.commit(`messages/${removedDevicesID[0]}/clear`)
          } else if (removedDevicesID.length === currentDevicesID.length) {
            removedDevicesID.forEach((id) => {
              this.$store.commit(`messages/${id}/clear`)
            })
          }
          removedDevicesID.forEach((id) => this.devicesState[id].initStatus = null)
          break
        }
        case 'add': {
          const addedDeviceID = activeDevicesID.filter(id => !currentDevicesID.includes(id))
          if (addedDeviceID) {
            addedDeviceID.forEach((id) => {
              this.devicesState[id].initStatus = false
              this.initDevice(id)
            })
          }
          break
        }
      }
      if (this.map && L.DomUtil.hasClass(this.map._container, 'crosshair-cursor-enabled')) {
        L.DomUtil.removeClass(this.map._container, 'crosshair-cursor-enabled')
      }
    },
    selectedDeviceId (id) {
      if (id && this.devicesState[id] && this.devicesState[id].initStatus === true) {
        this.flyToDevice(id)
      }
    },
    isSelectedDeviceFollowed (state) {
      if (state === true && this.devicesState[this.selectedDeviceId] && this.devicesState[this.selectedDeviceId].initStatus === true) {
        /* user enabled following the selected device on map */
        /* center on device, if device is already initialized */
        this.centerOnDevice(this.selectedDeviceId, this.map.getZoom())
      }
    },
    devicesColors: {
      deep: true,
      handler(newVal, oldVal){
        this.activeDevicesID.forEach(id => {
          if (newVal[id] !== oldVal[id]) {
            this.updateDeviceColorOnMap(id, newVal[id])
          }
        })
      },
    },
    'params.needShowNamesOnMap': function (needShowNamesOnMap) {
      Object.keys(this.markers).forEach(id => {
        const currentDevice = this.activeDevices.filter(device => device.id === parseInt(id))[0],
          position = this.messages[id] && this.messages[id].length ? [this.messages[id][this.messages[id].length - 1]['position.latitude'], this.messages[id][this.messages[id].length - 1]['position.longitude']] : [],
          name = currentDevice.name || `#${id}`
        if (this.markers[id].main && this.markers[id].main instanceof L.Marker) {
          this.markers[id].main.remove()
          this.map.removeLayer(this.markers[id].accuracy)
          this.initMarker(id, name, position)
        }
      })
    },
    'params.needShowLBSPoints': function(showLBS) {
      // Refresh all points and tracks for all devices when the LBS toggle changes
      this.activeDevicesID.forEach(id => {
        // Refresh points
        this.initAllPoints(id)
        
        // Rebuild tracks with/without LBS points
        if (this.tracks[id] && this.tracks[id] instanceof L.Polyline) {
          // Update the track with filtered coordinates
          const newCoords = this.getLatLngArrByDevice(id);
          this.tracks[id].setLatLngs(newCoords);
          
          // If we have active tails or overviews, update them too
          if (this.tracks[id].tail && this.tracks[id].tail instanceof L.Polyline) {
            // Rebuild the tail with filtered points
            const tailCoords = this.messages[id]
              .filter(msg => 
                !(!showLBS && msg['position.source'] && 
                  msg['position.source'].toLowerCase() === 'lbs')
              )
              .map(msg => [msg['position.latitude'], msg['position.longitude']]);
            this.tracks[id].tail.setLatLngs(tailCoords);
          }
          
          // Handle overview track if it exists
          if (this.tracks[id].overview && this.tracks[id].overview instanceof L.Polyline) {
            // If in play mode, stop and restart to reflect the new filtered points
            if (this.player.status === 'play') {
              this.playerDataStop({ id });
              this.playerDataPlay({ id });
            }
          }
        }
      })
    },
    'params.needShowInvalidPositionMessages' : function () {
      this.activeDevicesID.forEach(async (id) => {
        // reinit device data, as now device may have last position from telemetry
        await this.getDeviceData(id)
        if (id === this.selectedDeviceId) {
          this.centerOnDevice(id)
        }
        // Refresh all points
        this.initAllPoints(id)
      })
    },
    date (date, prev) {
      if (prev) {
        this.player.status = 'stop'
        this.player.currentMsgIndex = null
        this.activeDevicesID.forEach(async (id) => {
          // Clear existing points before getting new data
          this.clearAllPoints(id)
          await this.getDeviceData(id)
          // Refresh all points after data is updated
          this.initAllPoints(id)
        })
        
        // Auto-zoom after all data is loaded and points are refreshed
        // Date range changes typically load a lot of new data points
        // The longer delay ensures all async operations have completed
        setTimeout(() => {
          // Only auto-zoom if we're not following a specific device
          if (!this.isSelectedDeviceFollowed) {
            this.autoZoomToFitPoints();
          }
        }, 500); // Added a longer delay to ensure all data is loaded
      }
    },
    /**
     * Handle device selection change
     * Adjusts map view to focus on the selected device
     * 
     * When a device is selected, this:
     * 1. Auto-zooms to fit all points for the selected device with padding
     * 2. Resets any telemetry tail data to start fresh
     * 
     * @param {number|string} active - The newly selected device ID
     */
    selected (active) {
      if (!this.isFlying && this.tracks[active] && this.tracks[active] instanceof L.Polyline) {
        // Use the auto-zoom method instead of direct fitBounds
        // Filter points to only include the selected device
        const allPoints = [];
        if (this.messages[active] && this.messages[active].length) {
          const devicePoints = this.messages[active].filter(msg => {
            // Only include points with valid coordinates
            if (!msg['position.latitude'] || !msg['position.longitude']) return false;
            
            // Skip LBS points if the toggle is off
            if (!this.params.needShowLBSPoints && 
                msg['position.source'] && 
                msg['position.source'].toLowerCase() === 'lbs') {
              return false;
            }
            
            return true;
          }).map(msg => [msg['position.latitude'], msg['position.longitude']]);
          
          allPoints.push(...devicePoints);
        }
        
        if (allPoints.length) {
          // Create a bounds object with generous padding for better view
          const bounds = L.latLngBounds(allPoints);
          this.map.fitBounds(bounds, {
            padding: [
              120,  // Top padding (px) - more space for date selector
              200   // Left/right/bottom padding (px) - for message boxes and controls
            ],
            maxZoom: 18,      // Don't zoom in too far
            animate: true     // Smooth animation
          });
        }
      }
      
      if (this.devicesState[active] && this.devicesState[active].telemetryTail && this.devicesState[active].telemetryTail.length > 0) {
        /* when selected device has changed, discard previous telemetry tail, if any so that to start drawing tail from the scratch */
        this.devicesState[active].telemetryTail = []
      }
    }
  },
  created () {
    this.debouncedUpdateStateByMessages = debounce(this.updateStateByMessages, 100)
    this.debouncedUpdateStateByTelemetry = debounce(this.updateStateByTelemetry, 5)
    this.activeDevicesID = this.activeDevices.map((device) => device.id)
    this.activeDevicesID.forEach((id) => {
      this.registerModule(id)
      this.$store.commit(`messages/${id}/setSortBy`, 'timestamp')
      this.$store.commit(`messages/${id}/setReverse`, true)
      this.devicesState[id].initStatus = false
      this.initDevice(id)
    })
    Vue.connector.socket.on('offline', () => {
      this.$store.commit('setSocketOffline', true)
    })
    Vue.connector.socket.on('connect', () => {
      this.$store.commit('setSocketOffline', false)
    })
  },
  destroyed () {
    Vue.connector.socket.off('offline')
    Vue.connector.socket.off('connect')
    this.activeDevicesID.forEach(async (id) => {
      this.$store.unregisterModule(['messages', id])
    })
  },
  mounted () {
    this.initMap()
  },
  components: { Queue, ColorModal }
}
</script>

<style lang="stylus">
  .leaflet-control-layers
    top 110px
    .leaflet-control-layers-toggle
      width 24px
      height 24px
      background-size 20px
  .leaflet-container.crosshair-cursor-enabled
    cursor crosshair
  .leaflet-control.leaflet-bar
    top 50px
    left 6px
    border none
    .leaflet-control-zoom-in, .leaflet-control-zoom-out
      background-color #fff
      color #333
      border-color #666
      box-shadow 0 0 15px rgba(0,0,0,0.5)
    .leaflet-control-zoom-in
      border-top-left-radius 3px
      border-top-right-radius 3px
    .leaflet-control-zoom-out
      border-bottom-left-radius 3px
      border-bottom-right-radius 3px
  .my-flag-icon__inner
    font-size 35px
    position relative
    top -20px
    left 2px
  .my-div-icon
    z-index 2000!important
    .my-div-icon__name
      line-height 20px
      font-size .9rem
      font-weight bolder
      position absolute
      top 0
      left 30px
      max-width 200px
      text-overflow ellipsis
      overflow hidden
      background-color rgba(0,0,0,0.5)
      color #fff
      border-radius 5px
      padding 0 5px
      border 1px solid white
      box-shadow 3px 3px 10px #999
  .direction
    border 2px solid black
    border-radius 50% 0 50% 50%
    background-color white
    opacity .5
    height 20px
    width 20px
  .my-round-marker
    height 10px
    width 10px
    border-radius 50%
    background-color $red-7
    transform scale(1)
    box-shadow 0 0 0 0 rgba(255, 82, 82, 1)
    animation pulse 2s infinite

  @keyframes pulse {
    0% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0 rgba(255, 82, 82, 0.7);
    }
    70% {
      transform: scale(1);
      box-shadow: 0 0 0 10px rgba(255, 82, 82, 0);
    }
    100% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0 rgba(255, 82, 82, 0);
    }
  }
  
  /* Custom pulse colors for GPS (black) */
  .my-round-marker[style*="background-color: #000000"] {
    box-shadow: 0 0 0 0 rgba(0, 0, 0, 1);
    animation: pulse-gps 2s infinite;
  }
  
  @keyframes pulse-gps {
    0% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0 rgba(0, 0, 0, 0.7);
    }
    70% {
      transform: scale(1);
      box-shadow: 0 0 0 10px rgba(0, 0, 0, 0);
    }
    100% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0 rgba(0, 0, 0, 0);
    }
  }
  
  /* Custom pulse colors for LBS (orange) */
  .my-round-marker[style*="background-color: #FFA500"] {
    box-shadow: 0 0 0 0 rgba(255, 165, 0, 1);
    animation: pulse-lbs 2s infinite;
  }
  
  @keyframes pulse-lbs {
    0% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0 rgba(255, 165, 0, 0.7);
    }
    70% {
      transform: scale(1);
      box-shadow: 0 0 0 10px rgba(255, 165, 0, 0);
    }
    100% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0 rgba(255, 165, 0, 0);
    }
  }
  
  /* Info box styles */
  .info-box-container {
    background: white;
    border-radius: 6px;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.25);
    max-width: 280px;
    overflow: hidden;
    position: absolute;
    top: 100px; /* Position 100px from the top */
    right: 10px;
    z-index: 10000; /* Very high z-index to ensure it's on top */
  }
  
  .info-box {
    padding: 0;
    font-size: 12px;
  }
  
  .info-box-header {
    background: #f5f5f5;
    padding: 5px 10px;
    text-align: right;
    border-bottom: 1px solid #ddd;
  }
  
  .info-box-close {
    cursor: pointer;
    font-size: 16px;
    font-weight: bold;
    color: #666;
  }
  
  .info-box-close:hover {
    color: #000;
  }
  
  .info-box-content {
    width: 100%;
    border-collapse: collapse;
  }
  
  .info-box-content tr {
    border-bottom: 1px solid #f0f0f0;
  }
  
  .info-box-content tr:last-child {
    border-bottom: none;
  }
  
  .info-box-content td {
    padding: 8px 10px;
  }
  
  .info-box-content td:first-child {
    width: 40%;
    color: #666;
  }
  
  .info-box-link {
    display: block;
    text-align: center;
    padding: 8px 0;
    background: #FFFFFF; /* White background */
    color: #3B82F6; /* Blue text */
    text-decoration: none;
    border-radius: 4px;
    margin: 5px 0;
    font-weight: bold;
    letter-spacing: 0.5px; 
    border: 2px solid #3B82F6; /* Blue outline */
  }
  
  .info-box-link:hover {
    background: #F0F7FF; /* Very light blue on hover */
  }
  
  /* Custom container for the info box */
  #map .info-box-container {
    margin-top: 100px; /* Move down by 100px */
    right: 10px;
  }
</style>
