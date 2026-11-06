#!/usr/bin/env bash
# 构建 Release → 签名 → 打 dmg → 生成 Sparkle appcast。
# 用法：SIGN_IDENTITY="LingoLens Self Sign" DOWNLOAD_URL_PREFIX="https://.../releases/download/v0.1.2/" scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"            # 默认 ad-hoc；建议换成固定的自签名证书
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"  # dmg 的下载地址前缀（以 / 结尾）
BUILD_DIR=build
DIST_DIR=dist

xcodegen generate
xcodebuild -project LingoLens.xcodeproj -scheme LingoLens -configuration Release \
  -derivedDataPath "$BUILD_DIR" CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build | tail -n 3

APP="$BUILD_DIR/Build/Products/Release/LingoLens.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST_DIR/LingoLens-$VERSION.dmg"

# 整包重签一次，保证内嵌的 Sparkle.framework 与主程序签名身份一致。
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

mkdir -p "$DIST_DIR"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname LingoLens -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

SPARKLE_BIN="$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin"
ARGS=()
[[ -n "$DOWNLOAD_URL_PREFIX" ]] && ARGS+=(--download-url-prefix "$DOWNLOAD_URL_PREFIX")
"$SPARKLE_BIN/generate_appcast" ${ARGS[@]+"${ARGS[@]}"} "$DIST_DIR"

echo "✅ $DMG"
echo "✅ $DIST_DIR/appcast.xml —— 上传 dmg 到下载地址，appcast.xml 放到 SPARKLE_FEED_URL"
