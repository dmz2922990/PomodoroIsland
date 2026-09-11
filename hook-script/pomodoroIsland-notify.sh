#!/bin/bash
# PomodoroIsland agent hook 脚本：通过本地 MCP(127.0.0.1:9527) 把 agent 事件接入岛屿
# 用法: pomodoroIsland-notify.sh <agent> <mode>
#   mode:
#     permission-request  PermissionRequest hook → 权限请求转发到岛屿「允许/拒绝」，阻塞等待；
#                         超时或岛屿不可用时输出空 + exit 0，回落 zcode 默认确认 UI
#     ask-user-question   PreToolUse hook (matcher=AskUserQuestion) → 把问题转发到岛屿作答，
#                         通过 updatedInput 注入 answers 并放行；失败时回落 zcode 默认提问 UI
#     其他值（含 stop）   被动通知：发出即返回，不阻塞
# 可用环境变量: CLAUDE_SESSION_ID / ZCODE_PROJECT_DIR (由 hook 运行时注入)
#   POMODORO_ISLAND_ASK_TIMEOUT: 覆盖岛屿等待秒数（调试用，默认 permission=120 / 每题=90）
#   POMODORO_ISLAND_MCP_URL:     覆盖 MCP 地址（调试用）
# 前置: 阻塞模式需要系统安装 python3（JSON 处理）；缺失或出错时一律放行回落，不阻断会话

AGENT="${1:-unknown-agent}"
MODE="${2:-unknown-hook}"
MCP_URL="${POMODORO_ISLAND_MCP_URL:-http://127.0.0.1:9527/mcp}"
LOG=/tmp/pomodoroIsland-notify.log
DB="$HOME/.zcode/cli/db/db.sqlite"

log() { echo "[$(date '+%H:%M:%S')] agent=$AGENT mode=$MODE $*" >> "$LOG"; }

# 会话标题：zcode 会话优先反查可读标题，其他场景退回当前目录名
session_title() {
  local SESSION_ID="${CLAUDE_SESSION_ID:-}" TITLE=""
  if [ "$AGENT" = "zcode" ] && [ -n "$SESSION_ID" ] && [ -f "$DB" ]; then
    TITLE=$(sqlite3 "file:$DB?mode=ro" "SELECT title FROM session WHERE id='$SESSION_ID' LIMIT 1" 2>/dev/null)
  fi
  [ -z "$TITLE" ] && TITLE="$(basename "${ZCODE_PROJECT_DIR:-$PWD}")"
  if [ ${#TITLE} -gt 40 ]; then TITLE="${TITLE:0:40}…"; fi
  printf '%s' "$TITLE" | tr -d '\n\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

case "$MODE" in
  permission-request|ask-user-question)
    command -v python3 >/dev/null 2>&1 || { log "python3 缺失, 回落默认 UI"; exit 0; }
    input_file=$(mktemp "${TMPDIR:-/tmp}/pomodoroIsland-hook.XXXXXX")
    trap 'rm -f "$input_file"' EXIT
    cat > "$input_file" 2>/dev/null
    AGENT="$AGENT" MODE="$MODE" MCP_URL="$MCP_URL" INPUT_FILE="$input_file" \
    SESSION_TITLE="$(session_title)" \
    ASK_TIMEOUT="${POMODORO_ISLAND_ASK_TIMEOUT:-}" \
    python3 <<'PYEOF'
import json, os, sys, urllib.request

AGENT = os.environ["AGENT"]
MODE = os.environ["MODE"]
MCP_URL = os.environ["MCP_URL"]
# 多 session/多 agent 并发时用「agent·会话名」作来源身份：岛屿上可分辨来源，
# 且单来源并发上限按会话分别计数（App 侧交互卡上限：全局 8 / 单来源 4）
SESSION = os.environ.get("SESSION_TITLE", "")[:16]
SOURCE = f"{AGENT}·{SESSION}" if SESSION else AGENT
ASK_TIMEOUT = int(os.environ["ASK_TIMEOUT"]) if os.environ.get("ASK_TIMEOUT") else (30 if MODE == "permission-request" else 25)

def mcp_ask_user(args, island_timeout):
    """调用 MCP ask_user（阻塞到用户响应或岛屿超时）。返回响应 dict；任何失败抛异常。"""
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                          "params": {"name": "ask_user",
                                     "arguments": dict(args, timeoutSeconds=island_timeout, source=SOURCE)}},
                         ensure_ascii=False)
    req = urllib.request.Request(MCP_URL, data=payload.encode("utf-8"),
                                 headers={"Content-Type": "application/json"}, method="POST")
    # 禁用代理，保证 127.0.0.1 直连；超时需大于岛屿侧 deadline，等它先结算
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=island_timeout + 15) as r:
        body = json.loads(r.read().decode("utf-8"))
    if body.get("error"):
        raise RuntimeError(str(body["error"].get("message", "mcp error")))
    result = body.get("result") or {}
    if result.get("isError"):
        raise RuntimeError(str((result.get("content") or [{}])[0].get("text", "ask_user failed")))
    return json.loads(result["content"][0]["text"])

def ask_island(title, message, args):
    """发一个岛屿提问，用户已作答则返回响应 dict，否则 None（超时/关闭/岛屿不可用）。"""
    try:
        resp = mcp_ask_user(dict(args, title=title, message=message), ASK_TIMEOUT)
    except Exception as e:
        print(f"ask_user failed: {e}", file=sys.stderr)
        return None
    return resp if resp.get("status") == "answered" else None

def emit(obj):
    print(json.dumps(obj, ensure_ascii=False))

def truncate(s, n):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[:n] + "…"

def permission_mode():
    with open(os.environ["INPUT_FILE"]) as f:
        hook = json.load(f)
    tool = hook.get("tool_name") or hook.get("toolName") or "?"
    tin = hook.get("tool_input") or hook.get("toolInput") or {}
    # AskUserQuestion 不在此弹权限卡：提问环节（ask-user-question 模式）已让用户在岛屿作答过，
    # 用户关闭提问卡 = 放弃岛屿应答，此处回落 zcode 原生流程（原生权限 + 原生提问 UI），
    # 避免同一工具调用在岛上被打断两次
    if tool == "AskUserQuestion":
        return
    reason = hook.get("reason") or "该操作需要你的确认"
    summary = summarize_input(tin)
    message = truncate(f"{tool}：{reason}", 160)
    if summary:
        message += "\n" + truncate(summary, 120)
    resp = ask_island(f"🔐 {AGENT} 请求权限", message,
                      {"type": "buttons", "buttons": ["允许", "拒绝"]})
    if not resp:
        return  # 输出空 + exit 0 → 回落 zcode 默认确认 UI
    if resp.get("clicked") == "允许":
        emit({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                     "decision": {"behavior": "allow"}}})
    elif resp.get("clicked") == "拒绝":
        emit({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
                                     "decision": {"behavior": "deny",
                                                  "message": "用户在 PomodoroIsland 岛屿上拒绝了该操作"}}})


def summarize_input(tin):
    """权限卡摘要：优先取可读键；AskUserQuestion 类输入汇总问题文本而不是倾倒原始 JSON"""
    if not isinstance(tin, dict):
        return ""
    qs = tin.get("questions")
    if isinstance(qs, list) and qs:
        texts = "／".join(str(q.get("question", "")) for q in qs
                          if isinstance(q, dict) and q.get("question"))
        if texts:
            return f"{len(qs)} 个问题：{texts}"
    for k in ("command", "file_path", "path", "pattern", "url", "query", "prompt"):
        if isinstance(tin.get(k), str) and tin[k].strip():
            return tin[k]
    return json.dumps(tin, ensure_ascii=False)

def ask_user_question_mode():
    with open(os.environ["INPUT_FILE"]) as f:
        hook = json.load(f)
    tin = hook.get("tool_input") or hook.get("toolInput") or {}
    questions = tin.get("questions") if isinstance(tin, dict) else None
    if not isinstance(questions, list):
        return
    answers = {}
    total = len(questions)
    for i, q in enumerate(questions, 1):
        if not isinstance(q, dict):
            continue
        opts = [{"label": o.get("label", ""), "detail": o.get("description", "")}
                for o in (q.get("options") or []) if isinstance(o, dict)]
        if not (2 <= len(opts) <= 6):
            continue  # 岛屿 choice 需要 2-6 个选项，放弃此题（回落默认 UI 处理）
        multi = bool(q.get("multiSelect"))
        header = truncate(q.get("header") or f"问题 {i}/{total}", 20)
        resp = ask_island(f"❓ [{i}/{total}] {header}", truncate(q.get("question", ""), 200),
                          {"type": "choice", "options": opts, "multiSelect": multi,
                           # 多选不放开自定义输入，避免输入框提交丢掉已勾选项
                           **({} if multi else {"allowInput": True})})
        if not resp:
            continue
        ans = resp.get("text") or ", ".join(resp.get("selected") or []) or resp.get("clicked") or ""
        if ans.strip() and q.get("question"):
            answers[q["question"]] = ans
    if not answers:
        return  # 全部未答 → 回落 zcode 默认提问 UI
    new_input = dict(tin)
    new_input["answers"] = answers
    emit({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                 "permissionDecision": "allow",
                                 "permissionDecisionReason": "用户已在 PomodoroIsland 岛屿上作答",
                                 "updatedInput": new_input}})

try:
    if MODE == "permission-request":
        permission_mode()
    else:
        ask_user_question_mode()
except Exception as e:
    print(f"hook error: {e}", file=sys.stderr)
# 始终 exit 0：无输出 = 不干预，交回 zcode 默认流程
sys.exit(0)
PYEOF
    log "blocking mode done"
    exit 0
    ;;

  *)
    # 被动通知（stop 与其他通用事件）：发出即返回，不等待用户
    if [ "$MODE" != "stop" ]; then NOTICE="事件: $MODE"; else NOTICE="任务完成"; fi
    LEVEL="success"; [ "$MODE" != "stop" ] && LEVEL="info"
    TITLE=$(session_title)
    log "notify title=$TITLE"
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
      -X POST "$MCP_URL" \
      -H 'Content-Type: application/json' \
      -d "$payload" >/dev/null 2>&1
    exit 0
    ;;
esac
