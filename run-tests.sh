#!/bin/zsh
# 只编译设备状态的纯逻辑层与测试入口，不依赖 SwiftUI / AppKit。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

xcrun swiftc -O -parse-as-library -swift-version 5 \
  "$ROOT/Sources/DeviceState.swift" \
  "$ROOT/Tests/DeviceStateTests.swift" \
  -o "$TMP/device-state-tests"

"$TMP/device-state-tests"
