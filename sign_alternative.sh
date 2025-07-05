#!/bin/bash

echo "🔧 Alternative signing approach for PatchMaster..."

# Build the package first without signing
echo "📦 Building unsigned package..."
productbuild --distribution package/distribution.xml --package-path package/ PatchMaster-unsigned.pkg

# Sign the package separately with different timestamp options
echo "🔐 Attempting to sign package..."

# Method 1: Use Apple's timestamp with increased timeout
if timeout 60 productbuild --distribution package/distribution.xml --package-path package/ --sign "Developer ID Installer: Somesh Pathak (LJ3W53UDG4)" --timestamp PatchMaster.pkg; then
    echo "✅ Package signed successfully with Apple timestamp"
    rm -f PatchMaster-unsigned.pkg
    exit 0
fi

# Method 2: Try without timestamp (creates a warning but works)
echo "⚠️  Apple timestamp failed, trying without timestamp..."
if productbuild --distribution package/distribution.xml --package-path package/ --sign "Developer ID Installer: Somesh Pathak (LJ3W53UDG4)" --timestamp=none PatchMaster.pkg; then
    echo "⚠️  Package signed without timestamp (will work but not recommended for distribution)"
    rm -f PatchMaster-unsigned.pkg
    exit 0
fi

# Method 3: Use codesign on the already built package
echo "🔄 Trying codesign approach..."
if codesign --sign "Developer ID Installer: Somesh Pathak (LJ3W53UDG4)" --timestamp PatchMaster-unsigned.pkg; then
    mv PatchMaster-unsigned.pkg PatchMaster.pkg
    echo "✅ Package signed using codesign"
    exit 0
fi

echo "❌ All signing methods failed"
exit 1 