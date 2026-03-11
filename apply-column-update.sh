#!/bin/bash
# Script to directly apply column changes to the node_modules file

ACTIONS_PATH="node_modules/qvirtualscroll/src/store/modules/devicesMessages/actions.js"

# Make a backup of the original file
cp $ACTIONS_PATH $ACTIONS_PATH.bak

# Replace the default columns with our updated ones including the new fields
sed -i 's/const defaultCols = \[\(.*\)\]/const defaultCols = \["timestamp", "device.name", "report.code", "power.reason.text", "google.address", "position.satellites", "position.source", "position.accuracy", "position.hdop", "battery.level", "lastCmdQueue", "lastCmdExec"\]/' $ACTIONS_PATH

# Make sure the "etc" column is enabled
sed -i '/needEtc/s/const needEtc = sysColsNeedInitFlags.etc/const needEtc = true/' $ACTIONS_PATH

echo "Column update patch applied successfully!"
echo "Please restart the application to see the changes."