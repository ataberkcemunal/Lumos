#!/bin/sh
# Requires a logged-in macOS GUI session; no real lamps are contacted.
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
# Older installed SDK avoids a missing SwiftUI macro plugin in some macOS betas.
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
# Exclude only the application entry point, exercising the production controller and views.
find "$PROJECT_DIR/Sources/Lumos" -name '*.swift' ! -name 'LumosApp.swift' -print > "$TEST_DIR/sources"
while IFS= read -r source; do
    set -- "$@" "$source"
done < "$TEST_DIR/sources"
swiftc -parse-as-library -swift-version 6 -sdk "$SDK_PATH" -module-cache-path "$TEST_DIR/modules" "$@" "$PROJECT_DIR/Tests/MenuBarRegression.swift" -o "$TEST_DIR/MenuBarRegression"
"$TEST_DIR/MenuBarRegression" > "$TEST_DIR/result"
cat "$TEST_DIR/result"
# AppKit can exit early without failure when no GUI session is accessible.
# Require the completion marker so that cannot be mistaken for a passed test.
grep -q '^PASS: menu-bar lifecycle' "$TEST_DIR/result"
