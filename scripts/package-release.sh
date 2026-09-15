#!/usr/bin/env bash
#
# 打发布包：NotchSwitch-<版本>.dmg
#
# 产物结构：DMG 里放 NotchSwitch.app + 指向 /Applications 的软链，
# 用户打开后拖进去即完成安装（macOS 的惯例装法）。
#
# 用法:
#   ./scripts/package-release.sh          # release 构建 + 打 DMG
#   ./scripts/package-release.sh --no-build
#
# 说明:
#   - 版本号读自 Resources/Info.plist 的 CFBundleShortVersionString
#   - DMG 输出到 ~/Library/Developer/NotchSwitch/build/（与 .app 同目录，不上 Spotlight）
#   - App 的签名仍由 build-app.sh 负责；DMG 本身不需要签名
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NO_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --no-build) NO_BUILD=1 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$NO_BUILD" -eq 0 ]]; then
  ./scripts/build-app.sh release
fi

APP="$HOME/Library/Developer/NotchSwitch/build/NotchSwitch.app"
if [[ ! -d "$APP" ]]; then
  echo "构建产物不存在: $APP（先跑 ./scripts/build-app.sh）" >&2
  exit 1
fi

VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
DMG="$HOME/Library/Developer/NotchSwitch/build/NotchSwitch-$VERSION.dmg"

echo "==> 组装 DMG 暂存目录"
STAGE="$(mktemp -d)/NotchSwitch $VERSION"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/NotchSwitch.app"
ln -s /Applications "$STAGE/Applications"

echo "==> 生成 $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "NotchSwitch $VERSION" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -fs HFS+ \
  "$DMG"

echo "==> 完成: $DMG"
echo "    校验: hdiutil attach \"$DMG\" && open /Volumes/NotchSwitch*"
