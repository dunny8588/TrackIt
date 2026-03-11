/**
 * Generate HTML for device/position markers
 * 
 * @param {string} name - Name of the device
 * @param {string} color - Color for the marker
 * @param {boolean} needNames - Whether to show names
 * @param {string} positionSource - Source of position (GPS, LBS)
 * @param {boolean} isMostRecent - If this is the most recent point
 * @param {number|null} sequenceNumber - Optional sequence number (1 for newest, increasing for older)
 * @returns {string} HTML for the marker
 */
export default function getIconHTML (name, color, needNames, positionSource = null, isMostRecent = false, sequenceNumber = null) {
  // Set color based on position source: black for GPS, orange for LBS
  let fillColor = color;
  let strokeColor = "#000";
  let strokeWidth = 1;
  let textColor = "#fff"; // White text for visibility
  
  if (positionSource) {
    if (positionSource.toLowerCase() === 'gps') {
      fillColor = '#000000'; // Black for GPS
      textColor = '#fff';    // White text on black
    } else if (positionSource.toLowerCase() === 'lbs') {
      fillColor = '#FFA500'; // Orange for LBS
      textColor = '#000';    // Black text on orange
    }
    
    // Make the stroke bolder for the most recent point
    if (isMostRecent) {
      strokeWidth = 3;
    }
  }
  
  // Create SVG with optional sequence number
  const icon = `
    <svg xmlns="http://www.w3.org/2000/svg" version="1.0" width="20" height="20" viewBox="0 0 20 20">
      <circle cx="10" cy="10" r="7" fill="${fillColor}" stroke="${strokeColor}" stroke-width="${strokeWidth}" />
      ${sequenceNumber !== null ? 
        `<text x="10" y="13" text-anchor="middle" font-family="Arial, sans-serif" 
               font-size="9" font-weight="bold" fill="${textColor}">${sequenceNumber}</text>` : 
        ''}
    </svg>
  `
  
  const html = `
    <div class="my-div-icon__inner">${icon}</div>
    ${needNames ? `<div class="my-div-icon__name">${name}</div>` : ''}
  `
  return html
}