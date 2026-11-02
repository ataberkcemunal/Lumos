#!/bin/sh
# Regenerates icon.png, Resources/Lumos.iconset and Resources/Lumos.icns from scripts/make-icon.swift.
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift -module-cache-path "$TEST_DIR/modules" "$PROJECT_DIR/scripts/make-icon.swift" "$PROJECT_DIR/icon.png"
ICONSET="$PROJECT_DIR/Resources/Lumos.iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$PROJECT_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$PROJECT_DIR/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$PROJECT_DIR/Resources/Lumos.icns"
echo "$PROJECT_DIR/Resources/Lumos.icns"
