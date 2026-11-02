#!/bin/sh
# Offline store checks: a fake lamp on 127.0.0.1:38899 and favorite limits; no real lamps are contacted.
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swiftc -parse-as-library -swift-version 6 -sdk "$SDK_PATH" -module-cache-path "$TEST_DIR/modules" \
    "$PROJECT_DIR/Sources/Lumos/WizClient.swift" "$PROJECT_DIR/Sources/Lumos/Models.swift" \
    "$PROJECT_DIR/Sources/Lumos/LightStore.swift" "$PROJECT_DIR/Tests/CommandPathRegression.swift" \
    -o "$TEST_DIR/command-path-test"
"$TEST_DIR/command-path-test"
swiftc -parse-as-library -swift-version 6 -sdk "$SDK_PATH" -module-cache-path "$TEST_DIR/modules" \
    "$PROJECT_DIR/Sources/Lumos/WizClient.swift" "$PROJECT_DIR/Sources/Lumos/Models.swift" \
    "$PROJECT_DIR/Sources/Lumos/LightStore.swift" "$PROJECT_DIR/Tests/FavoritesRegression.swift" \
    -o "$TEST_DIR/favorites-test"
"$TEST_DIR/favorites-test"
