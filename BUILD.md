# PatchMaster Build & Distribution Guide

## Project Structure

```
PatchMaster_wip/
├── PatchMaster/              # Main SwiftUI app source
├── PatchMasterDaemon/        # Privileged daemon source
├── PatchMasterTests/         # Unit tests
├── PatchMasterUITests/       # UI tests
├── PatchMaster.xcodeproj/    # Xcode project
├── package/                  # Package build output
├── build-package.sh          # Main build script for distribution
└── sign-package.sh           # Package signing script
```

## Building for Development

### Build and Run App
```bash
xcodebuild -scheme PatchMaster -configuration Release
```

### Build Daemon Only
```bash
xcodebuild -scheme PatchMasterDaemon -configuration Release -derivedDataPath /tmp/PatchMaster-Build build
```

### Install Daemon for Testing
```bash
# Build
xcodebuild -scheme PatchMasterDaemon -configuration Release -derivedDataPath /tmp/PatchMaster-Build build

# Install
sudo launchctl unload /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist 2>/dev/null
sudo cp /tmp/PatchMaster-Build/Build/Products/Release/PatchMasterDaemon /Library/PrivilegedHelperTools/
sudo launchctl load /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
```

## Building Distribution Package

### Full Package Build (Recommended)
```bash
./build-package.sh
```

This will:
1. Build the app and daemon
2. Create proper package structure
3. Embed daemon in app bundle
4. Generate installer package
5. Sign with Developer ID
6. Notarize with Apple
7. Staple notarization ticket

### Manual Package Signing
```bash
./sign-package.sh PatchMaster.pkg
```

## Development Utilities

### Fix IPC Permissions (if daemon not responding)
```bash
sudo rm -rf /tmp/patchmaster-ipc
sudo mkdir -p /tmp/patchmaster-ipc/{requests,responses,progress}
sudo chmod -R 777 /tmp/patchmaster-ipc
sudo launchctl unload /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
sudo launchctl load /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
```

### Check Daemon Status
```bash
# Check if loaded
launchctl list | grep com.mavericklabs.patchmaster.daemon

# Check IPC directories
ls -lah /tmp/patchmaster-ipc/{requests,responses,progress}

# View daemon logs
sudo log show --predicate 'process == "PatchMasterDaemon"' --last 5m
```

### Uninstall for Clean Testing
```bash
# Stop daemon
sudo launchctl unload /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist 2>/dev/null

# Remove files
sudo rm -f /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
sudo rm -f /Library/PrivilegedHelperTools/PatchMasterDaemon
sudo rm -rf /Applications/PatchMaster.app
sudo rm -rf /tmp/patchmaster-ipc

# Kill processes
killall PatchMaster 2>/dev/null
sudo killall PatchMasterDaemon 2>/dev/null
```

## Code Signing Requirements

### Certificates Needed
- **Developer ID Application**: For signing the app
- **Developer ID Installer**: For signing the package

### Verify Certificates
```bash
security find-identity -v -p codesigning
```

### Verify Signatures
```bash
# App signature
codesign -dvv /Applications/PatchMaster.app

# Package signature
pkgutil --check-signature PatchMaster.pkg
```

## Notarization

Credentials are stored in Keychain:
- Profile: `notarytool-password`
- Apple ID: somesh.pathak@mavericklabs.no
- Team ID: LJ3W53UDG4

Check notarization status:
```bash
xcrun notarytool history --keychain-profile "notarytool-password"
```

## Troubleshooting

### Daemon Not Responding
1. Check IPC permissions: `ls -lah /tmp/patchmaster-ipc`
2. Check daemon is loaded: `launchctl list | grep patchmaster`
3. Check daemon logs: `sudo log show --predicate 'process == "PatchMasterDaemon"' --last 5m`
4. Reload daemon: See "Fix IPC Permissions" above

### App Shows "All up to date" When Updates Available
1. Daemon may not be running
2. Check response files: `ls -lh /tmp/patchmaster-ipc/responses/`
3. Manually trigger: Click Refresh button

### Installation Fails
1. Check app signature: `codesign -dvv package/payload/PatchMaster.app`
2. Verify daemon exists in bundle: `ls -lh package/payload/PatchMaster.app/Contents/Resources/Daemon/`
3. Check postinstall script: `cat package/scripts/postinstall`
