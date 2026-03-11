#!/bin/bash
# Script to install custom default columns in TrackIt

# Define the path to the actions.js file
ACTIONS_PATH="node_modules/qvirtualscroll/src/store/modules/devicesMessages/actions.js"

# Make a backup of the original file
cp $ACTIONS_PATH $ACTIONS_PATH.bak

# Replace the default columns with custom ones
sed -i 's/const defaultCols = \[\(.*\)\]/const defaultCols = \["timestamp", "device.name", "report.code", "power.reason.text", "google.address", "position.satellites", "position.source", "position.accuracy", "position.hdop", "battery.level", "lastCmdQueue", "lastCmdExec"\]/' $ACTIONS_PATH

# Add the "etc" column by default
sed -i '/needEtc/s/const needEtc = sysColsNeedInitFlags.etc/const needEtc = true/' $ACTIONS_PATH

echo "Custom columns patch applied successfully!"
echo "Please rebuild the application with 'npm run build' for production deployment."