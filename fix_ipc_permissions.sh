#!/bin/bash

echo "🔧 Fixing PatchMaster IPC permissions..."

# Stop daemon
sudo launchctl unload /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist 2>/dev/null || true

# Remove and recreate IPC directory with proper permissions
sudo rm -rf /tmp/patchmaster-ipc

# Create directory structure
sudo mkdir -p /tmp/patchmaster-ipc/requests
sudo mkdir -p /tmp/patchmaster-ipc/responses  
sudo mkdir -p /tmp/patchmaster-ipc/progress

# Set proper permissions (777 = read/write/execute for everyone)
sudo chmod -R 777 /tmp/patchmaster-ipc

echo "✅ IPC directory permissions fixed:"
ls -la /tmp/patchmaster-ipc/

# Restart daemon
sudo launchctl load /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist

echo "🚀 Daemon restarted - PatchMaster should now work correctly!"
echo ""
echo "📱 Launch PatchMaster.app to test" 