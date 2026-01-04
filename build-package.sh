#!/bin/bash

echo "🔧 Building distribution package..."

# Clean up any existing package directory
rm -rf package/

echo "📦 Copying app..."
mkdir -p package/{payload,scripts}

# Build the app first if it doesn't exist
echo "🔨 Building PatchMaster.app..."
xcodebuild -project PatchMaster.xcodeproj -scheme PatchMaster -configuration Release build

echo "🔨 Building PatchMasterDaemon..."
xcodebuild -project PatchMaster.xcodeproj -scheme PatchMasterDaemon -configuration Release build

# Find the built app in DerivedData
DERIVED_DATA_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "PatchMaster.app" -type d | grep Release | head -1)
DAEMON_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "PatchMasterDaemon" -type f -perm +111 | grep Release | head -1)

if [ -n "$DERIVED_DATA_PATH" ] && [ -d "$DERIVED_DATA_PATH" ]; then
    cp -R "$DERIVED_DATA_PATH" package/payload/
    echo "✅ App copied from DerivedData: $DERIVED_DATA_PATH"
else
    echo "❌ Failed to find built PatchMaster.app in DerivedData"
    exit 1
fi

echo "🔧 Creating daemon resources..."
# Create daemon directories in app bundle
mkdir -p package/payload/PatchMaster.app/Contents/Resources/Daemon
mkdir -p package/payload/PatchMaster.app/Contents/Resources/LaunchDaemons

# Copy freshly built daemon from DerivedData
if [ -n "$DAEMON_PATH" ] && [ -f "$DAEMON_PATH" ]; then
    cp "$DAEMON_PATH" package/payload/PatchMaster.app/Contents/Resources/Daemon/
    echo "✅ Daemon copied from DerivedData: $DAEMON_PATH"
else
    echo "❌ Failed to find built PatchMasterDaemon in DerivedData"
    exit 1
fi
cp PatchMasterDaemon/com.mavericklabs.patchmaster.daemon.plist package/payload/PatchMaster.app/Contents/Resources/LaunchDaemons/

echo "🔐 Signing daemon with Developer ID..."
# Sign daemon BEFORE signing app bundle - critical for launchd to accept it
if codesign --force --sign "Developer ID Application: Somesh Pathak (LJ3W53UDG4)" --timestamp --options runtime package/payload/PatchMaster.app/Contents/Resources/Daemon/PatchMasterDaemon; then
    echo "✅ Daemon signed with timestamp"
elif codesign --force --sign "Developer ID Application: Somesh Pathak (LJ3W53UDG4)" --timestamp=none --options runtime package/payload/PatchMaster.app/Contents/Resources/Daemon/PatchMasterDaemon; then
    echo "⚠️  Daemon signed without timestamp"
else
    echo "❌ Failed to sign daemon"
    exit 1
fi

echo "🔐 Re-signing app bundle with daemon files..."
# Re-sign the app bundle after adding daemon files - try with timestamp first, then without
if codesign --force --sign "Developer ID Application: Somesh Pathak (LJ3W53UDG4)" --timestamp --options runtime --deep package/payload/PatchMaster.app; then
    echo "✅ App bundle signed with timestamp"
elif codesign --force --sign "Developer ID Application: Somesh Pathak (LJ3W53UDG4)" --timestamp=none --options runtime --deep package/payload/PatchMaster.app; then
    echo "⚠️  App bundle signed without timestamp"
else
    echo "❌ Failed to sign app bundle"
    exit 1
fi

# Verify the signature
if codesign -v --verify --verbose=4 package/payload/PatchMaster.app; then
    echo "✅ App bundle signature verified"
else
    echo "❌ App bundle signature verification failed"
    exit 1
fi

# Create scripts
cat > package/scripts/preinstall << 'EOL'
#!/bin/bash
/bin/launchctl bootout system /Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist 2>/dev/null
/usr/bin/killall "PatchMaster" 2>/dev/null
/usr/bin/killall "PatchMasterDaemon" 2>/dev/null
exit 0
EOL

cat > package/scripts/postinstall << 'EOL'
#!/bin/bash
echo "🚀 PatchMaster Installation Starting..."

# Log the installation process for debugging
echo "$(date): PatchMaster installation started" >> /var/log/patchmaster-install.log

# Create directories
mkdir -p "/Library/PrivilegedHelperTools"

# Copy daemon files from app bundle - FIXED PATH for Intune deployment
APP_PATH="/Applications/PatchMaster.app"
echo "🔍 Looking for app at: $APP_PATH"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ ERROR: PatchMaster.app not found at $APP_PATH" >> /var/log/patchmaster-install.log
    echo "❌ ERROR: PatchMaster.app not found at $APP_PATH"
    exit 1
fi

echo "✅ Found PatchMaster.app at $APP_PATH"

# Copy daemon files from app bundle
echo "📋 Copying daemon files..."
cp "$APP_PATH/Contents/Resources/Daemon/PatchMasterDaemon" "/Library/PrivilegedHelperTools/"
cp "$APP_PATH/Contents/Resources/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist" "/Library/LaunchDaemons/"

# Verify files were copied
if [ ! -f "/Library/PrivilegedHelperTools/PatchMasterDaemon" ]; then
    echo "❌ ERROR: Failed to copy PatchMasterDaemon" >> /var/log/patchmaster-install.log
    echo "❌ ERROR: Failed to copy PatchMasterDaemon"
    exit 1
fi

if [ ! -f "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist" ]; then
    echo "❌ ERROR: Failed to copy daemon plist" >> /var/log/patchmaster-install.log
    echo "❌ ERROR: Failed to copy daemon plist"
    exit 1
fi

# Set permissions for daemon files
chmod 755 "/Library/PrivilegedHelperTools/PatchMasterDaemon"
chown root:wheel "/Library/PrivilegedHelperTools/PatchMasterDaemon"
chmod 644 "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist"
chown root:wheel "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist"

# Create log file
touch /var/log/patchmaster.log
chmod 644 /var/log/patchmaster.log

# Setup IPC directories with proper permissions (CRITICAL FIX)
echo "🔧 Setting up IPC communication..."
rm -rf /tmp/patchmaster-ipc
mkdir -p /tmp/patchmaster-ipc/requests
mkdir -p /tmp/patchmaster-ipc/responses
mkdir -p /tmp/patchmaster-ipc/progress

# Set proper permissions for IPC (777 = read/write for both daemon and app)
chmod -R 777 /tmp/patchmaster-ipc
echo "✅ IPC directories created with proper permissions"

# Load and start daemon
echo "🚀 Loading daemon..."
launchctl load "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist"

# Wait for daemon to start
sleep 3

# Verify daemon is running
if launchctl list | grep -q "com.mavericklabs.patchmaster.daemon"; then
    echo "✅ PatchMaster daemon started successfully"
    echo "$(date): Daemon started successfully" >> /var/log/patchmaster-install.log
else
    echo "⚠️ Daemon may not have started - will retry"
    launchctl unload "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist" 2>/dev/null || true
    sleep 2
    launchctl load "/Library/LaunchDaemons/com.mavericklabs.patchmaster.daemon.plist"
    
    # Final check
    if launchctl list | grep -q "com.mavericklabs.patchmaster.daemon"; then
        echo "✅ PatchMaster daemon started successfully on retry"
        echo "$(date): Daemon started successfully on retry" >> /var/log/patchmaster-install.log
    else
        echo "❌ ERROR: Failed to start daemon after retry" >> /var/log/patchmaster-install.log
        echo "❌ ERROR: Failed to start daemon after retry"
    fi
fi

# Remove quarantine attributes if they exist
xattr -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "🎉 PatchMaster installation completed successfully!"
echo "$(date): Installation completed successfully" >> /var/log/patchmaster-install.log
echo "📱 The app is ready to use and will automatically detect updates"
exit 0
EOL

chmod +x package/scripts/*

echo "📂 Embedding resources..."
# Create distribution package
echo "🔨 Building component package..."
pkgbuild --root package/payload --scripts package/scripts --identifier com.mavericklabs.patchmaster --install-location /Applications package/component.pkg

# Create distribution.xml
cat > package/distribution.xml << 'EOL'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>PatchMaster</title>
    <options customize="never" require-scripts="true" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="PatchMaster">
        <pkg-ref id="com.mavericklabs.patchmaster"/>
    </choice>
    <pkg-ref id="com.mavericklabs.patchmaster" version="1.0">component.pkg</pkg-ref>
</installer-gui-script>
EOL

echo "🔐 Building and signing distribution package..."
# Try multiple signing approaches
if productbuild --distribution package/distribution.xml --package-path package/ --sign "Developer ID Installer: Somesh Pathak (LJ3W53UDG4)" --timestamp PatchMaster.pkg; then
    echo "✅ Package signed successfully with timestamp"
elif productbuild --distribution package/distribution.xml --package-path package/ --sign "Developer ID Installer: Somesh Pathak (LJ3W53UDG4)" --timestamp=none PatchMaster.pkg; then
    echo "⚠️  Package signed without timestamp (not recommended for distribution)"
else
    echo "❌ Failed to sign package"
    exit 1
fi

echo "🎉 Distribution package created: PatchMaster.pkg" 