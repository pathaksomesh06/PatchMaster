#!/bin/bash

# PatchMaster Package Signing Script
# Handles timestamp issues with productsign (macOS compatible)

if [ $# -lt 3 ]; then
    echo "Usage: $0 <identity> <input.pkg> <output.pkg>"
    echo "Example: $0 'Developer ID Installer: Somesh Pathak (LJ3W53UDG4)' input.pkg output.pkg"
    exit 1
fi

IDENTITY="$1"
INPUT_PKG="$2"
OUTPUT_PKG="$3"

echo "🔐 Signing package: $INPUT_PKG"
echo "📝 Identity: $IDENTITY"
echo "📦 Output: $OUTPUT_PKG"

# Method 1: Try with Apple's timestamp (with timeout using background process)
echo "🕐 Attempting with timestamp..."
(
    productsign --sign "$IDENTITY" --timestamp "$INPUT_PKG" "$OUTPUT_PKG" 
) &
SIGN_PID=$!

# Wait up to 60 seconds for the process to complete
for i in {1..60}; do
    if ! kill -0 $SIGN_PID 2>/dev/null; then
        wait $SIGN_PID
        if [ $? -eq 0 ]; then
            echo "✅ Package signed successfully with timestamp"
            exit 0
        fi
        break
    fi
    sleep 1
done

# Kill the process if it's still running
kill $SIGN_PID 2>/dev/null
wait $SIGN_PID 2>/dev/null

# Method 2: Try without timestamp
echo "⚠️  Timestamp failed, trying without timestamp..."
if productsign --sign "$IDENTITY" --timestamp=none "$INPUT_PKG" "$OUTPUT_PKG"; then
    echo "⚠️  Package signed without timestamp (still valid and secure)"
    exit 0
fi

echo "❌ Failed to sign package"
exit 1 