/**
 * Generate HTML for device/position markers
 *
 * @param {string} name - Name of the device
 * @param {string} color - Color for the marker
 * @param {boolean} needNames - Whether to show names
 * @param {string} positionSource - Source of position (GPS, LBS)
 * @param {boolean} isMostRecent - If this is the most recent point
 * @param {number|null} sequenceNumber - Optional sequence number (1 for newest, increasing for older)
 * @param {number|null} stackCount - Number of overlapping points at this location (shown as badge if > 1)
 * @returns {string} HTML for the marker
 */
export default function getIconHTML (name, color, needNames, positionSource = null, isMostRecent = false, sequenceNumber = null, stackCount = null) {
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
    
    // Most recent point: green fill with bold stroke
    if (isMostRecent) {
      fillColor = '#00AA00';
      textColor = '#fff';
      strokeWidth = 3;
    }
  }
  
  // Badge SVG elements (red circle with count, top-right corner) - inside SVG to avoid CSS transform issues
  const badgeSvg = (stackCount && stackCount > 1) ? `
      <circle cx="26" cy="2" r="9" fill="#e53935" stroke="#fff" stroke-width="1.5" />
      <text x="26" y="6" text-anchor="middle" font-family="Arial, sans-serif"
            font-size="12" font-weight="bold" fill="#fff">${stackCount}</text>` : ''

  // Create SVG with optional sequence number and badge
  // Expand viewBox to accommodate badge in top-right corner
  const svgWidth = (stackCount && stackCount > 1) ? 38 : 28;
  const icon = `
    <svg xmlns="http://www.w3.org/2000/svg" version="1.0" width="${svgWidth}" height="28" viewBox="${(stackCount && stackCount > 1) ? '-2 -8 40 36' : '0 0 28 28'}">
      <circle cx="14" cy="14" r="10" fill="${fillColor}" stroke="${strokeColor}" stroke-width="${strokeWidth}" />
      ${sequenceNumber !== null ?
        `<text x="14" y="18" text-anchor="middle" font-family="Arial, sans-serif"
               font-size="12" font-weight="bold" fill="${textColor}">${sequenceNumber}</text>` :
        ''}${badgeSvg}
    </svg>
  `

  const html = `
    <div class="my-div-icon__inner">${icon}</div>
    ${needNames ? `<div class="my-div-icon__name">${name}</div>` : ''}
  `
  return html
}