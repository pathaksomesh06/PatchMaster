#!/bin/bash

echo "🧹 Cleaning up previous PatchMaster installation..."

# Stop and remove daemon
sudo launchctl unload /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
sudo rm -f /Library/PrivilegedHelperTools/PatchMasterDaemon

# Kill any running processes
sudo killall "PatchMaster" 2>/dev/null || true
sudo killall "PatchMasterDaemon" 2>/dev/null || true

# Remove the app from Applications
sudo rm -rf /Applications/PatchMaster.app

# Remove log file
sudo rm -f /var/log/patchmaster.log

echo "✅ Cleanup completed!"
echo ""
echo "🚀 Now you can install the new package:"
echo "   Double-click PatchMaster-final-working.pkg"
echo ""
echo "🔍 After installation, run: ./test_daemon.sh" 