#!/bin/bash
# 通用 agent hook 通知脚本: 调用本地 MCP 通知接口(PomodoroIsland)发送桌面通知
# 用法: pomodoroIsland-notify.sh <agent> <hook>
#   agent: 发起通知的 agent 名称, 如 zcode / claude / codex
#   hook:  触发的钩子事件, 如 stop
# 示例(zcode 的 Stop hook): bash ~/.zcode/hooks/pomodoroIsland-notify.sh zcode stop
# 可用环境变量: CLAUDE_SESSION_ID / ZCODE_PROJECT_DIR (由各 agent 的 hook 运行时注入)

AGENT="${1:-unknown-agent}"
HOOK="${2:-unknown-hook}"
SESSION_ID="${CLAUDE_SESSION_ID:-}"
DB="$HOME/.zcode/cli/db/db.sqlite"

# 任务名: zcode 会话优先反查可读标题, 其他场景退回当前目录名
TITLE=""
if [ "$AGENT" = "zcode" ] && [ -n "$SESSION_ID" ] && [ -f "$DB" ]; then
  TITLE=$(sqlite3 "file:$DB?mode=ro" "SELECT title FROM session WHERE id='$SESSION_ID' LIMIT 1" 2>/dev/null)
fi
[ -z "$TITLE" ] && TITLE="$(basename "${ZCODE_PROJECT_DIR:-$PWD}")"

# 截断过长标题, 去掉换行, 做 JSON 转义
if [ ${#TITLE} -gt 40 ]; then TITLE="${TITLE:0:40}…"; fi
TITLE=$(printf '%s' "$TITLE" | tr -d '\n\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')

# 事件 → 通知级别与文案
case "$HOOK" in
  stop) LEVEL="success"; NOTICE="任务完成" ;;
  *)    LEVEL="info";    NOTICE="事件: $HOOK" ;;
esac

echo "[$(date '+%H:%M:%S')] agent=$AGENT hook=$HOOK session=$SESSION_ID title=$TITLE" >> /tmp/pomodoroIsland-notify.log

payload=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "notify",
    "arguments": {
      "title": "🔔${AGENT} ${NOTICE}",
      "message": "${TITLE}",
      "level": "${LEVEL}",
      "autoDismiss": 10,
      "source": "${AGENT}"
    }
  }
}
EOF
)

curl -s --connect-timeout 2 --max-time 5 \
  -X POST http://127.0.0.1:9527/mcp \
  -H 'Content-Type: application/json' \
  -d "$payload" >/dev/null 2>&1

exit 0
