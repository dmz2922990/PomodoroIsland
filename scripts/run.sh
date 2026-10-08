#!/bin/bash
# PomodoroIsland 启动脚本：已在运行则不动，未运行则启动最新构建的 .app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/PomodoroIsland.app"
BIN="Contents/MacOS/PomodoroIsland"

# 已在运行：直接退出（避免多实例）
if pgrep -f "PomodoroIsland.app/${BIN}" > /dev/null 2>&1; then
    echo "PomodoroIsland 已在运行 (pid $(pgrep -f "PomodoroIsland.app/${BIN}" | head -1))"
    exit 0
fi

# .app 不存在则先构建
if [ ! -d "${APP}" ]; then
    echo "未找到 ${APP}，开始构建…"
    ./scripts/make-app.sh
fi

open "${APP}"
echo "已启动 PomodoroIsland"
