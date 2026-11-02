#!/bin/sh
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swiftc -parse-as-library -swift-version 6 -sdk "$SDK_PATH" -module-cache-path "$TEST_DIR/modules" "$PROJECT_DIR/Sources/Lumos/WizClient.swift" "$PROJECT_DIR/Tests/DiscoveryRegression.swift" -o "$TEST_DIR/discovery-test"
"$TEST_DIR/discovery-test"
swiftc -parse-as-library -swift-version 6 -sdk "$SDK_PATH" -module-cache-path "$TEST_DIR/modules" "$PROJECT_DIR/Sources/Lumos/WizClient.swift" "$PROJECT_DIR/Sources/Lumos/Models.swift" "$PROJECT_DIR/Sources/Lumos/LightStore.swift" "$PROJECT_DIR/Tests/DiscoveryStoreRegression.swift" -o "$TEST_DIR/store-test"
"$TEST_DIR/store-test"
