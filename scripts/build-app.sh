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

# Replacing the binary under a running copy breaks that copy: its signature no
# longer matches the app on disk, so macOS blocks its local-network access.
# Quit it first and start the new build afterwards.
WAS_RUNNING=0
if pgrep -xq Lumos; then
  WAS_RUNNING=1
  osascript -e 'tell application id "com.ataberk.lumos" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Lumos || break; sleep 0.5; done
  pkill -x Lumos 2>/dev/null || true
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/Lumos" "$APP_DIR/Contents/MacOS/Lumos"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Lumos.icns" "$APP_DIR/Contents/Resources/Lumos.icns"
codesign --force --deep --sign - "$APP_DIR"
if [ "$WAS_RUNNING" = 1 ]; then open "$APP_DIR"; fi
echo "$APP_DIR"
