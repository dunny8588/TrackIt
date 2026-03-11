// Utility script to update default columns for TrackIt

// The columns you want to display
const preferredColumns = [
  'timestamp',
  'device.name',
  'report.code',
  'power.reason.text', 
  'google.address',
  'position.satellites', 
  'position.source',
  'position.accuracy',
  'position.hdop',
  'battery.level',
  'lastCmdQueue',  // New field
  'lastCmdExec',   // New field
  'etc'  // Keep this to show other parameters
];

// Helper function to get default column schema
function getDefaultColsSchema(columns) {
  return {
    activeSchema: '_default',
    schemas: {
      _default: {
        name: '_default',
        cols: columns.map(name => ({ name, width: 150 }))
      }
    },
    enum: columns.reduce((res, name) => {
      res[name] = { name };
      if (name.match(/timestamp$/)) {
        const locale = new Date().toString().match(/([-+][0-9]+)\s/)[1];
        res[name].addition = `${locale.slice(0, 3)}:${locale.slice(3)}`;
        res[name].type = '';
        res[name].unit = '';
      }
      return res;
    }, {})
  };
}

// Get localStorage
function getLocalStorageConfig() {
  try {
    // Get all localStorage keys
    console.log("Available localStorage keys:");
    Object.keys(localStorage).forEach(key => {
      console.log(` - ${key}`);
    });

    // Look for keys containing "cols" which would be related to column configuration
    const colsKeys = Object.keys(localStorage).filter(key => key.includes('cols'));
    console.log("\nColumn configuration keys:");
    colsKeys.forEach(key => {
      console.log(` - ${key}`);
    });

    // If you found the key for column configuration, print its current value
    if (colsKeys.length > 0) {
      console.log("\nCurrent column configuration:");
      colsKeys.forEach(key => {
        try {
          const value = JSON.parse(localStorage.getItem(key));
          console.log(` - ${key}: ${JSON.stringify(value, null, 2)}`);
        } catch (e) {
          console.log(` - ${key}: [Error parsing JSON]`);
        }
      });
    }
  } catch (e) {
    console.error("Error accessing localStorage:", e);
  }
}

// Update localStorage with new configuration
function updateColumnConfig() {
  try {
    // Get keys related to column configuration
    const colsKeys = Object.keys(localStorage).filter(key => key.includes('cols'));
    
    if (colsKeys.length === 0) {
      console.log("No column configuration found in localStorage");
      return;
    }
    
    // For each configuration key, update the column schema
    colsKeys.forEach(key => {
      try {
        console.log(`Updating configuration for key: ${key}`);
        
        // Get current configuration
        const currentConfig = JSON.parse(localStorage.getItem(key));
        
        // Create new schema with preferred columns
        const newSchema = getDefaultColsSchema(preferredColumns);
        
        // Update the configuration
        // This depends on the exact structure of your config
        // If this doesn't work, we'll need to check the actual structure
        
        localStorage.setItem(key, JSON.stringify(newSchema));
        console.log(`Updated column configuration for ${key}`);
      } catch (e) {
        console.error(`Error updating ${key}:`, e);
      }
    });
    
    console.log("Column configuration updated. Please refresh the TrackIt application.");
  } catch (e) {
    console.error("Error updating column configuration:", e);
  }
}

// Display the current localStorage configuration
console.log("==== Current LocalStorage Configuration ====");
getLocalStorageConfig();

// Update the column configuration to include the new fields
updateColumnConfig();

console.log("\nTo update column configuration, edit this file to uncomment the updateColumnConfig() line,");
console.log("then run it again in the browser console.");