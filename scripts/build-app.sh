#!/bin/sh
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="/Applications/Lumos.app"

cd "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/.cache/clang"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.cache/clang"
# The default SDK can briefly lead the installed compiler after a macOS beta update.
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift build --disable-sandbox -c release -debug-info-format none
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/Lumos" "$APP_DIR/Contents/MacOS/Lumos"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Lumos.icns" "$APP_DIR/Contents/Resources/Lumos.icns"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
