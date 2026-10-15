#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_DIR/module-cache"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" \
    -swift-version 5 -warnings-as-errors \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework AppKit -framework Foundation \
    "$PROJECT_DIR/AppDelegate.swift" \
    "$PROJECT_DIR/CodexUsageClient.swift" \
    "$PROJECT_DIR/Tests/SmokeTests.swift" \
    -o "$BUILD_DIR/CodexLeftTests"
TEST_OUTPUT="$("$BUILD_DIR/CodexLeftTests")"
printf '%s\n' "$TEST_OUTPUT"
if [[ "$TEST_OUTPUT" != *"全部验证通过"* ]]; then
    echo "验证未完成：AppKit 测试需要能连接窗口服务的 macOS 桌面会话。" >&2
    exit 1
fi
