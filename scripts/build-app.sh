#!/usr/bin/env bash
#
# 构建 NotchSwitch.app
#
# 用法:
#   ./scripts/build-app.sh            # release 构建
#   ./scripts/build-app.sh debug      # debug 构建
#
# 签名：
#   优先使用固定自签名身份（./scripts/setup-signing.sh 建立），
#   保证 designated requirement 基于证书而非 cdhash，TCC 权限才能长期有效。
#   找不到身份时退回 ad-hoc 签名，并明确警告。
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=./signing.conf
source "$ROOT/scripts/signing.conf"

APP_NAME="NotchSwitch"
# 构建产物放 ~/Library/Developer 而不是项目目录：
# ~/Library 默认不被 Spotlight 索引；放项目里会多出一个能被 Spotlight/启动台
# 搜到的 NotchSwitch.app（实测踩中：与 /Applications 的正主并列出现）。
# SwiftPM 的 .build/ 以点开头天然不被索引，只有这里组装的 .app 需要挪。
BUILD_DIR="$HOME/Library/Developer/NotchSwitch/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "构建产物不存在: $BIN_PATH" >&2
  exit 1
fi

echo "==> 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# 重启后签名钥匙串会被锁上，导致 codesign 报 errSecInternalComponent
if [[ -f "$SIGN_KEYCHAIN_PATH" ]]; then
  security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN_PATH" >/dev/null 2>&1 || true
fi

# 注意：这里「不能」用 `find-identity -v`。
# -v 只列 valid identities（会做信任链校验），我们的自签名证书未加入系统信任设置，
# 会被过滤掉；但 codesign 完全可以拿它签名（签名只需私钥+证书，信任只影响 Gatekeeper）。
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "==> 使用固定签名身份签名: $SIGN_IDENTITY"
  codesign --force --options runtime \
    --keychain "$SIGN_KEYCHAIN_PATH" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
  echo "==> 签名信息："
  codesign -dv --verbose=4 "$APP_DIR" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Signature" | sed 's/^/    /'
  echo "==> designated requirement（应为 certificate 而非 cdhash）："
  codesign -d -r- "$APP_DIR" 2>&1 | grep designated | sed 's/^/    /'
else
  echo "==> [警告] 未找到签名身份 '$SIGN_IDENTITY'，退回 ad-hoc 签名。" >&2
  echo "    ad-hoc 签名的 cdhash 每次构建都会变，系统会忘记已授予的权限，" >&2
  echo "    并导致「开关是开的但仍报未授权」。请先执行: ./scripts/setup-signing.sh" >&2
  codesign --force --sign - "$APP_DIR"
  codesign -d -r- "$APP_DIR" 2>&1 | grep designated | sed 's/^/    /' || true
fi

codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/    /'
echo "==> 完成: $APP_DIR"
echo "    运行: ./scripts/run-app.sh --no-build    （或 ./scripts/run-app.sh --install）"
