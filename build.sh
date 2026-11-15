#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Sign in a local, non-iCloud directory. FinderInfo / FileProvider xattrs are
# re-added under ~/Documents and make codesign fail.
BUILD_ROOT="${BUILD_ROOT:-$HOME/Downloads/ipa-dispatch-build}"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
APP="$BUILD_ROOT/IPA Dispatch.app"
DMG_STAGE="$BUILD_ROOT/dmg-stage"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building IPADispatch…"
# Compile from a local copy: the source tree lives in iCloud/FileProvider, whose
# metadata updates can make swiftc report "input file modified during build".
SRC_STAGE="$BUILD_ROOT/src"
mkdir -p "$SRC_STAGE"
cp "$ROOT"/Sources/*.swift "$SRC_STAGE/"
SDK=$(xcrun --sdk macosx --show-sdk-path)
# -disable-sandbox: SwiftUI 的宏插件 swift-plugin-server 在受限执行环境里
# 无法自行调用 sandbox-exec，否则 @State 等宏会报 "produced malformed response"。
# 普通终端下加这个 flag 同样安全，不影响编译产物。
xcrun swiftc -O -disable-sandbox -swift-version 5 -parse-as-library \
  -target arm64-apple-macos14.0 -sdk "$SDK" \
  "$SRC_STAGE"/*.swift \
  -o "$APP/Contents/MacOS/IPADispatch" \
  -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/sign-ios-ipa.sh"
# 内置证书含私钥，不纳入 git；从仓库 clone 后该目录可能不存在，
# 缺文件时跳过 chmod（脚本开了 set -e，直接 chmod 会中断构建）。
for bundled in "$APP/Contents/Resources/ipa-signing/bundled/cert.p12" \
               "$APP/Contents/Resources/ipa-signing/bundled/profile.mobileprovision"; do
  if [[ -f "$bundled" ]]; then chmod 600 "$bundled"; fi
done
chmod +x "$APP/Contents/MacOS/IPADispatch"
xattr -cr "$APP" || true

echo "Signing app (ad-hoc)…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
cp "$ROOT/README.md" "$DMG_STAGE/README.md"
cp "$ROOT/Assets/preview.png" "$DMG_STAGE/preview.png"
ln -s /Applications "$DMG_STAGE/Applications"
DIST="$ROOT/dist"
mkdir -p "$DIST"
rm -f "$DIST/IPA-Dispatch.dmg" "$DIST/IPA-Dispatch.zip"
hdiutil create -volname "IPA Dispatch" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DIST/IPA-Dispatch.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/IPA-Dispatch.zip"

echo
echo "App: $APP"
echo "DMG: $DIST/IPA-Dispatch.dmg"
echo "ZIP: $DIST/IPA-Dispatch.zip"
