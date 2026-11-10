#!/usr/bin/env bash
# 构建 Release → 签名 → 打 dmg → 生成 Sparkle appcast（写入 site/appcast.xml）→ 可选发布 GitHub Release。
# 用法：SIGN_IDENTITY="LingoLens Self Sign" PUBLISH=1 scripts/release.sh
#   PUBLISH=1 时自动 gh release create，并提交推送 site/appcast.xml 触发 Pages 部署。
set -euo pipefail
cd "$(dirname "$0")/.."

# 默认用固定的自签名证书签名。
#
# 为什么必须这样：ad-hoc 签名会让 App 的「指定要求」变成 cdhash 列表，每次构建都变。
# TCC（辅助功能 / 麦克风 / 屏幕录制）按这个要求记授权，于是用户每次更新都要重新授权，
# 而系统设置里那条旧记录还显示「已开启」，极难自查。固定证书后要求变成
# identifier + certificate root，跨版本稳定。
#
# 因此：找不到证书就**直接失败**。宁可发布被拦下来，也不要悄悄发出一个会让
# 所有用户丢授权的版本。
DEFAULT_IDENTITY="LingoLens Self Sign"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # 显式指定优先，仍要校验它真的存在。
  if [[ "$SIGN_IDENTITY" != "-" ]] \
    && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
    echo "❌ 找不到签名身份：$SIGN_IDENTITY"
    echo "   可用身份："
    security find-identity -v -p codesigning | sed 's/^/     /'
    exit 1
  fi
elif security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEFAULT_IDENTITY"; then
  SIGN_IDENTITY="$DEFAULT_IDENTITY"
  echo "🔏 使用固定证书签名：$SIGN_IDENTITY"
else
  echo "❌ 找不到签名证书「${DEFAULT_IDENTITY}」，已中止发布。"
  echo ""
  echo "   原因：ad-hoc 签名会让指定要求变成 cdhash，用户每次更新都会丢失"
  echo "        辅助功能 / 麦克风 / 屏幕录制授权，且系统设置里看不出来。"
  echo ""
  echo "   解决：在装有该证书备份的机器上执行（见 lingolens-signing-README.md）"
  echo '         security import lingolens-signing.p12 -k ~/Library/Keychains/login.keychain-db'
  echo '           -P "$(cat lingolens-signing.password)" -T /usr/bin/codesign -T /usr/bin/security'
  echo ""
  echo "   确实要发 ad-hoc 版本（仅限本地自测）时显式放行："
  echo "         SIGN_IDENTITY=- ALLOW_ADHOC_SIGNING=1 scripts/release.sh"
  exit 1
fi

# 只有显式写了 ALLOW_ADHOC_SIGNING=1 才允许 ad-hoc。
if [[ "$SIGN_IDENTITY" == "-" && "${ALLOW_ADHOC_SIGNING:-0}" != "1" ]]; then
  echo "❌ 拒绝用 ad-hoc 签名发布。"
  echo "   这种版本会让用户每次更新都重新授权隐私权限。"
  echo "   仅本地自测请显式放行：SIGN_IDENTITY=- ALLOW_ADHOC_SIGNING=1 scripts/release.sh"
  exit 1
fi
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

# 打印「指定要求」：TCC 认的就是它。这里出现 cdhash 说明签名不稳定，
# 用户每次更新都要重新授权，必须修掉。
REQUIREMENT=$(codesign -d -r- "$APP" 2>&1 | grep 'designated =>' | sed 's/^ *//')
echo "🔏 $REQUIREMENT"

# 最后一道闸：签完再确认一次。出现 cdhash 说明签名不稳定，不许发布。
if [[ "$REQUIREMENT" == *cdhash* ]]; then
  if [[ "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
    echo "⚠️  指定要求是 cdhash（ad-hoc 签名），已按 ALLOW_ADHOC_SIGNING=1 放行。"
  else
    echo "❌ 指定要求里是 cdhash，说明签名没有绑定到证书上。"
    echo "   这种版本会让用户每次更新都重新授权隐私权限，已中止。"
    exit 1
  fi
fi

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

# 签名私钥默认从登录钥匙串读取；指定 SPARKLE_ED_KEY_FILE 时用导出的密钥文件，
# 便于在没导入过钥匙串的机器上发布。
ED_KEY_ARGS=()
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  ED_KEY_ARGS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi

"$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  ${ED_KEY_ARGS[@]+"${ED_KEY_ARGS[@]}"} \
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
  echo "✅ 已发布 ${TAG}，Pages 部署完成后客户端即可检测到更新"
else
  echo "👉 手动发布：gh release create $TAG \"$DMG\"，然后提交推送 site/appcast.xml"
fi
