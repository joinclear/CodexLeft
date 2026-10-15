#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/CodexLeft.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" \
    -swift-version 5 -O -warnings-as-errors \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework AppKit -framework Foundation \
    "$PROJECT_DIR/main.swift" \
    "$PROJECT_DIR/AppDelegate.swift" \
    "$PROJECT_DIR/CodexUsageClient.swift" \
    -o "$APP_DIR/Contents/MacOS/CodexLeft"

codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"
echo "构建完成：$APP_DIR"
