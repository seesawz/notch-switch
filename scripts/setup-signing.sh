#!/usr/bin/env bash
#
# 建立「本机固定自签名身份」，用于本地开发签名。
#
# ── 为什么必须做 ──
# macOS 的 TCC 权限（辅助功能 / 屏幕录制）与**代码签名身份**绑定。
# ad-hoc 签名（codesign --sign -）的 designated requirement 是 cdhash：
#   designated => cdhash H"a1b2c3..."
# 每次重新构建 cdhash 都会变，于是：
#   1. 系统设置里的开关看着是「开」的，但 AXIsProcessTrusted() 返回 false
#   2. 系统再也不弹授权提示 —— 授权路径被彻底堵死
# 换成固定证书后，DR 变成：
#   designated => identifier "com.notchswitch.app" and certificate leaf = H"0485..."
# 重建也不变，权限就能长期有效。
#
# ── 两个必须绕开的坑（本脚本已处理）──
# 1. **不要用 p12**：OpenSSL 3.x 默认用 AES-256/SHA-256 导出 p12，
#    而 macOS 的 SecKeychainItemImport 只认老的 RC2/3DES + SHA-1，
#    会直接报 `MAC verification failed during PKCS12 import`。
#    改为分别导入 PEM 私钥与证书，绕开该不兼容。
# 2. **必须设置 key partition**：否则 codesign 拿不到私钥，
#    报 `errSecInternalComponent`。
#
# ── 为什么用独立钥匙串而不是登录钥匙串 ──
# 登录钥匙串的口令是用户登录密码，导入/访问时会弹 GUI 密码框，
# 脚本化执行容易卡住。独立钥匙串口令固定，全程无需交互。
#
# 撤销：./scripts/setup-signing.sh --uninstall
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./signing.conf
source "$ROOT/scripts/signing.conf"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------- 卸载 ----------

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "==> 从钥匙串搜索列表移除"
  REMAINING=""
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%\"}"; line="${line#\"}"
    [[ -z "$line" || "$line" == "$SIGN_KEYCHAIN_PATH" ]] && continue
    REMAINING="$REMAINING $line"
  done < <(security list-keychains -d user)
  # shellcheck disable=SC2086
  security list-keychains -d user -s $REMAINING
  echo "==> 删除钥匙串"
  security delete-keychain "$SIGN_KEYCHAIN_PATH" 2>/dev/null || true
  echo "完成，已恢复原钥匙串搜索列表。"
  exit 0
fi

# ---------- 已存在则跳过 ----------

if [[ -f "$SIGN_KEYCHAIN_PATH" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "✔ 签名身份已存在：$SIGN_IDENTITY"
  echo "  （如需重建：./scripts/setup-signing.sh --uninstall 后再跑一次）"
  exit 0
fi

# ---------- 生成证书 ----------

echo "==> 1/5 生成自签名代码签名证书（RSA 2048，10 年有效）"
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
  -subj "/CN=$SIGN_IDENTITY" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$WORK/key.pem" \
  -out "$WORK/cert.pem" 2>/dev/null

# ---------- 独立钥匙串 ----------

echo "==> 2/5 创建独立钥匙串"
security delete-keychain "$SIGN_KEYCHAIN_PATH" 2>/dev/null || true
security create-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN_PATH"
security set-keychain-settings "$SIGN_KEYCHAIN_PATH"   # 不设自动锁定
security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN_PATH"

echo "==> 3/5 导入私钥与证书（分别导入 PEM，绕开 p12 不兼容问题）"
security import "$WORK/key.pem" \
  -k "$SIGN_KEYCHAIN_PATH" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security import "$WORK/cert.pem" \
  -k "$SIGN_KEYCHAIN_PATH" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

echo "==> 4/5 设置 key partition（不设置会导致 codesign 报 errSecInternalComponent）"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$SIGN_KEYCHAIN_PASSWORD" \
  "$SIGN_KEYCHAIN_PATH" >/dev/null

echo "==> 5/5 追加到钥匙串搜索列表（保留原有项）"
REMAINING=""
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%\"}"; line="${line#\"}"
  [[ -z "$line" || "$line" == "$SIGN_KEYCHAIN_PATH" ]] && continue
  REMAINING="$REMAINING $line"
done < <(security list-keychains -d user)
# shellcheck disable=SC2086
security list-keychains -d user -s $REMAINING "$SIGN_KEYCHAIN_PATH"

# ---------- 校验 ----------

echo
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "✔ 签名身份建立成功："
  security find-identity -p codesigning | grep "$SIGN_IDENTITY"
  echo
  echo "（CSSMERR_TP_NOT_TRUSTED 是正常的：证书未加入系统信任设置。"
  echo "  签名只需要私钥+证书，不需要信任；信任只影响 Gatekeeper 启动校验，"
  echo "  而本地构建的 App 没有 quarantine 标记，不会被拦。）"
  echo
  echo "接下来："
  echo "  ./scripts/reset-permissions.sh   # 清掉之前 ad-hoc 签名留下的失效 TCC 记录"
  echo "  ./scripts/run-app.sh --install   # 用新身份重新签名构建，安装到 /Applications 并启动"
else
  echo "✘ 身份未生效，请把以下输出反馈给我：" >&2
  security find-identity -p codesigning || true
  exit 1
fi
