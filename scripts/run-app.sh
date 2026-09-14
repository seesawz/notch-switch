#!/usr/bin/env bash
#
# 构建并重启 App（推荐的日常调试入口）。
#
# 为什么需要这个脚本：
#   1. Info.plist 里有 LSMultipleInstancesProhibited=true（菜单栏应用不允许跑两份，
#      否则会有两个面板、两个菜单栏图标）。后果是旧实例还活着时，`open` 只会激活旧实例，
#      **不会启动新构建的版本**，表现成「改了代码但没生效」。
#   2. 从 build/ 和从 /Applications/ 运行会产生两套 TCC 记录，极易混乱。
#      所以这里明确区分两种模式，别混用。
#
# 用法:
#   ./scripts/run-app.sh              # 从 build/NotchSwitch.app 启动
#   ./scripts/run-app.sh debug        # debug 构建
#   ./scripts/run-app.sh --install    # 复制到 /Applications 并从那里启动（路径稳定，推荐）
#   ./scripts/run-app.sh --no-build   # 不重新构建，只重启
#
# ⚠️ 两种模式不要交替使用：授权是按「路径 + 签名」记录的，
#    在 build/ 授权完又换到 /Applications 跑，等于换了一个 App，需要重新授权。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INSTALL=0
NO_BUILD=0
CONFIG="release"

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --no-build) NO_BUILD=1 ;;
    debug|release) CONFIG="$arg" ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$NO_BUILD" -eq 0 ]]; then
  "$ROOT/scripts/build-app.sh" "$CONFIG"
fi

APP="$ROOT/build/NotchSwitch.app"
if [[ ! -d "$APP" ]]; then
  echo "构建产物不存在: $APP" >&2
  exit 1
fi

if [[ "$INSTALL" -eq 1 ]]; then
  TARGET="/Applications/NotchSwitch.app"
  echo "==> 安装到 $TARGET"
  pkill -x NotchSwitch 2>/dev/null || true
  sleep 1
  rm -rf "$TARGET"
  cp -R "$APP" "$TARGET"
  # 关键：删掉 build/ 里的副本。
  # 同一个 bundle id 存在两份时，LaunchServices 可能解析到旧路径（实测踩中：
  # 明明 open 的是 /Applications，实际跑起来的是 build/ 里那份）。
  # TCC 授权是「路径 + 签名」绑定的，两个位置各记一套，必然混乱。
  rm -rf "$ROOT/build/NotchSwitch.app"
  APP="$TARGET"
  echo "    已移除 build/ 副本，保证只有 /Applications 一个位置"
fi

echo "==> 结束已运行的实例"
pkill -x NotchSwitch 2>/dev/null || true
sleep 1

if pgrep -x NotchSwitch >/dev/null 2>&1; then
  echo "警告：仍有 NotchSwitch 进程存活，新版本可能不会生效" >&2
fi

echo "==> 启动 $APP"
open "$APP"

cat <<EOF

已启动：$APP

接下来可以：
  跟踪日志（重要事件）:
    /usr/bin/log stream --predicate 'subsystem == "com.notchswitch.app"'
  跟踪日志（含悬停等高频细节）:
    /usr/bin/log stream --debug --predicate 'subsystem == "com.notchswitch.app"'
  退出:
    pkill -x NotchSwitch

注意：请勿用 \`swift run\` 或直接执行 Contents/MacOS/NotchSwitch 来验证权限——
那样会继承终端进程的 TCC 归因，权限检测结果不可信（会误报「已授权」）。
EOF
