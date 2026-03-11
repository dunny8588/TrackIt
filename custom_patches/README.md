# TrackIt Custom Patches

This directory contains custom patches for the TrackIt application.

## Custom Columns Configuration

The `install_custom_columns.sh` script modifies the default columns displayed in the message list to show:

- timestamp
- device.name
- report.code
- power.reason.text
- google.address
- position.satellites
- position.source
- position.hdop
- battery.level
- etc (additional parameters)

### Installation

To apply this patch:

1. Make sure you're in the TrackIt root directory
2. Run the script:
   ```
   bash custom_patches/install_custom_columns.sh
   ```
3. Rebuild the application:
   ```
   npm run build
   ```

### Restoration

If you need to restore the original configuration:

1. Copy the backup file:
   ```
   cp node_modules/qvirtualscroll/src/store/modules/devicesMessages/actions.js.bak node_modules/qvirtualscroll/src/store/modules/devicesMessages/actions.js
   ```
2. Rebuild the application:
   ```
   npm run build
   ```

### Custom Modifications

If you wish to further customize the default columns, edit the `install_custom_columns.sh` script and modify the column list.