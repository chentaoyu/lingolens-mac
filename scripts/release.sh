#!/usr/bin/env bash
# 构建 Release → 签名 → 打 dmg → 生成 Sparkle appcast（写入 site/appcast.xml）→ 可选发布 GitHub Release。
# 用法：SIGN_IDENTITY="LingoLens Self Sign" PUBLISH=1 scripts/release.sh
#   PUBLISH=1 时自动 gh release create，并提交推送 site/appcast.xml 触发 Pages 部署。
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"            # 默认 ad-hoc；建议换成固定的自签名证书
REPO=chentaoyu/lingolens-mac
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

# 只用本次 dmg 生成 appcast：Sparkle 只需要最新一项，也避免旧版本套用错误的下载前缀。
TAG="v$VERSION"
FEED_DIR=$(mktemp -d)
cp "$DMG" "$FEED_DIR/"
"$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$FEED_DIR"
cp "$FEED_DIR/appcast.xml" site/appcast.xml
rm -rf "$FEED_DIR"
echo "✅ $DMG"
echo "✅ site/appcast.xml"

if [[ "${PUBLISH:-}" == "1" ]]; then
  gh release create "$TAG" "$DMG" --repo "$REPO" --title "LingoLens $VERSION" --generate-notes
  git add site/appcast.xml
  git commit -m "LingoLens macOS - chore(发布): 更新 appcast 至 $VERSION"
  git push
  echo "✅ 已发布 $TAG，Pages 部署完成后客户端即可检测到更新"
else
  echo "👉 手动发布：gh release create $TAG \"$DMG\"，然后提交推送 site/appcast.xml"
fi
