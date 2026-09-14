#!/usr/bin/env bash
#
# 清掉本 App 的 TCC 权限记录，用于修复「授权失败 / 开关是开的但仍提示未授权」。
#
# 什么情况下需要它：
#   TCC 把授权与「代码签名身份」绑定。用 ad-hoc 签名时每次构建身份都会变，
#   于是系统设置里可能残留一条旧的、对不上号的 NotchSwitch 记录：
#   开关显示为「开」，但 AXIsProcessTrusted() 依然返回 false，而且再也不会弹授权提示。
#   这种状态只能靠重置记录来解决。
#
# 用法:
#   ./scripts/reset-permissions.sh          # 重置辅助功能 + 屏幕录制
#   ./scripts/reset-permissions.sh all      # 重置本 App 的全部 TCC 记录
set -euo pipefail

BUNDLE_ID="com.notchswitch.app"

if [[ "${1:-}" == "all" ]]; then
  echo "==> 重置 $BUNDLE_ID 的全部 TCC 记录"
  tccutil reset All "$BUNDLE_ID" || true
else
  echo "==> 重置辅助功能权限记录"
  tccutil reset Accessibility "$BUNDLE_ID" || true
  echo "==> 重置屏幕录制权限记录"
  tccutil reset ScreenCapture "$BUNDLE_ID" || true
fi

echo ""
echo "完成。接下来："
echo "  1. ./scripts/setup-signing.sh   # 建立固定签名身份（避免再次失配）"
echo "  2. ./scripts/build-app.sh       # 重新构建"
echo "  3. 把 build/NotchSwitch.app 拖到「应用程序」文件夹（可选但推荐）"
echo "  4. 重新启动 App，会在系统设置里重新出现 NotchSwitch，届时打开开关"
