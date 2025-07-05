#!/bin/bash

echo "🔍 Testing PatchMaster Daemon Installation..."
echo "============================================"

# Check if daemon binary exists
if [ -f "/Library/PrivilegedHelperTools/PatchMasterDaemon" ]; then
    echo "✅ Daemon binary found"
    ls -la /Library/PrivilegedHelperTools/PatchMasterDaemon
else
    echo "❌ Daemon binary NOT found"
fi

echo ""

# Check if plist exists
if [ -f "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist" ]; then
    echo "✅ Daemon plist found"
    ls -la /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist
else
    echo "❌ Daemon plist NOT found"
fi

echo ""

# Check if daemon is loaded
if launchctl list | grep -q "com.mavericklabs.patchmaster.daemon"; then
    echo "✅ Daemon is loaded"
    launchctl list | grep "com.mavericklabs.patchmaster.daemon"
else
    echo "❌ Daemon is NOT loaded"
fi

echo ""

# Check if daemon is running
if pgrep -f "PatchMasterDaemon" > /dev/null; then
    echo "✅ Daemon is running"
    ps aux | grep PatchMasterDaemon | grep -v grep
else
    echo "❌ Daemon is NOT running"
fi

echo ""

# Check log file
if [ -f "/var/log/patchmaster.log" ]; then
    echo "✅ Log file exists"
    ls -la /var/log/patchmaster.log
    echo ""
    echo "📝 Recent log entries:"
    tail -5 /var/log/patchmaster.log 2>/dev/null || echo "No log entries yet"
else
    echo "❌ Log file NOT found"
fi

echo ""
echo "�� Test completed!" 