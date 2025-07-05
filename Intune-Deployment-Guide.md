# PatchMaster - Intune Deployment Guide

## 📦 Package Information
- **File**: `PatchMaster-Intune.pkg`
- **Size**: 2.17 MB
- **Status**: ✅ Signed with Apple Developer ID
- **Certificate**: Valid until 2029-07-07
- **Architecture**: Universal (Intel + Apple Silicon)

## 🚀 What This Package Does

**PatchMaster** is an automated app update management tool that:
- Scans installed macOS applications for available updates
- Integrates with Homebrew, IntuneBrew, and native update mechanisms
- Provides a clean UI for managing app updates
- Runs as a privileged daemon for system-level access

## ✅ Automatic Installation Process

When deployed via Intune, this package will:

1. **Install the app** to `/Applications/PatchMaster.app`
2. **Install the daemon** to `/Library/PrivilegedHelperTools/PatchMasterDaemon`
3. **Setup daemon service** with proper launch daemon configuration
4. **Create IPC communication** with correct permissions
5. **Start the daemon** automatically
6. **Verify installation** and provide status feedback

## 📋 Intune Configuration

### Application Settings
- **Install Behavior**: System
- **Device Restart Behavior**: No specific action
- **Return Codes**: Standard macOS installer codes
- **Requirements**: macOS 11.0 or later

### Detection Rules
**Rule Type**: File
- **Path**: `/Applications/PatchMaster.app/Contents/Info.plist`
- **Detection Method**: File or folder exists

**Alternative Rule Type**: Script
```bash
#!/bin/bash
if [ -f "/Applications/PatchMaster.app/Contents/Info.plist" ] && \
   [ -f "/Library/PrivilegedHelperTools/PatchMasterDaemon" ] && \
   launchctl list | grep -q "com.mavericklabs.patchmaster.daemon"; then
    echo "PatchMaster is installed and running"
    exit 0
else
    exit 1
fi
```

### Uninstall Command
```bash
#!/bin/bash
# Stop and remove daemon
launchctl unload /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist 2>/dev/null
rm -f /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
rm -f /Library/PrivilegedHelperTools/PatchMasterDaemon

# Remove app
rm -rf /Applications/PatchMaster.app

# Cleanup
rm -rf /tmp/patchmaster-ipc
rm -f /var/log/patchmaster.log

echo "PatchMaster uninstalled"
```

## 🛠️ Technical Details

### Components Installed
1. **Main Application**: `/Applications/PatchMaster.app`
   - SwiftUI-based user interface
   - Communicates with daemon via IPC
   - Displays available updates and manages installations

2. **Background Daemon**: `/Library/PrivilegedHelperTools/PatchMasterDaemon`
   - Runs as root for system access
   - Scans applications and checks for updates
   - Handles downloads and installations
   - Manages Homebrew, IntuneBrew integration

3. **Launch Daemon**: `/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist`
   - Automatically starts daemon on boot
   - Keeps daemon running
   - Managed by launchd

4. **IPC Directory**: `/tmp/patchmaster-ipc/`
   - Communication channel between app and daemon
   - Proper permissions for user/root interaction
   - Request/response file-based messaging

### Supported Update Sources
- **Homebrew Casks**: Most popular macOS applications
- **IntuneBrew**: Enterprise-focused app catalog
- **Native Updates**: Apps with built-in update mechanisms (e.g., Parallels)

## 🔧 Troubleshooting

### Common Issues & Solutions

**App shows "All apps up to date" immediately:**
- **Cause**: IPC permission issues
- **Solution**: Automatic (fixed in this package version)

**Daemon not running:**
```bash
sudo launchctl load /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
```

**Permission issues:**
```bash
sudo chmod -R 777 /tmp/patchmaster-ipc
```

**Check daemon status:**
```bash
sudo launchctl list | grep patchmaster
ps aux | grep PatchMasterDaemon
```

**View daemon logs:**
```bash
tail -f /var/log/patchmaster.log
```

## 📊 Expected Behavior

After installation:
1. **PatchMaster.app** appears in Applications
2. **Daemon starts** automatically (no user interaction needed)
3. **First launch** shows "Checking for updates..." with spinner
4. **Updates detected** for apps like Parallels, ChatGPT, browsers, etc.
5. **Users can install** updates with one click

## 🔒 Security & Permissions

- **App bundle**: Properly code-signed with Apple Developer ID
- **Daemon**: Runs with minimal required privileges
- **IPC**: Secure file-based communication
- **Updates**: Only installs from trusted sources
- **Quarantine**: Automatically removed to prevent Gatekeeper issues

## 📈 Deployment Recommendations

1. **Test deployment** on a small group first
2. **Monitor logs** for the first few installations
3. **Educate users** on the app's purpose and functionality
4. **Consider scheduling** for off-hours deployment
5. **Monitor updates** and plan for new app version deployments

---

**Package Ready for Intune Deployment!** 🎉

This package has been tested and includes all necessary fixes for proper operation in enterprise environments. 