# Agent Hooks（ZCode 事件接入）

除了 MCP 主动调用，岛屿还可以作为 **ZCode hook 的事件出口**：权限确认、AI 提问、任务完成等事件直接弹到刘海岛屿上，你不在编辑器窗口里也能响应。

脚本：[`hook-script/pomodoroIsland-notify.sh`](../hook-script/pomodoroIsland-notify.sh)（源码在仓库，安装到 `~/.zcode/hooks/` 使用）。

## 三种模式

| 模式 | 触发事件 | 行为 |
|---|---|---|
| `stop` | `Stop` | 被动通知「任务完成」，立即返回，不阻塞 |
| `permission-request` | `PermissionRequest` | 权限请求弹到岛屿「允许 / 拒绝」，**阻塞等待**；点了「允许」→ 放行，「拒绝」→ 带原因拒绝 |
| `ask-user-question` | `PreToolUse`（matcher=`AskUserQuestion`） | AI 的提问逐题弹到岛屿（单选/多选/自定义输入），答案通过 hook 的 `updatedInput` 注入 `answers`，AI 直接拿到结果 |

**回落保护（fail-open）**：阻塞模式若岛屿未运行、超时无响应或脚本出错，一律输出空 + exit 0，交回 ZCode 默认 UI，不会卡住会话。

- 权限请求默认等 120 秒（hook 超时 180s）
- 每个问题默认等 90 秒（hook 超时 400s，最多 4 题）
- 部分作答有效：只回答了 1/2 题，回答的那题也会注入

## ZCode 配置

`~/.zcode/cli/config.json`：

```json
{
  "hooks": {
    "enabled": true,
    "events": {
      "Stop": [
        { "hooks": [ { "type": "process", "command": "bash",
            "args": ["~/.zcode/hooks/pomodoroIsland-notify.sh", "zcode", "stop"],
            "timeoutMs": 10000, "statusMessage": "发送任务完成通知" } ] }
      ],
      "PermissionRequest": [
        { "hooks": [ { "type": "process", "command": "bash",
            "args": ["~/.zcode/hooks/pomodoroIsland-notify.sh", "zcode", "permission-request"],
            "timeoutMs": 180000, "statusMessage": "等待岛屿上确认权限请求" } ] }
      ],
      "PreToolUse": [
        { "matcher": "AskUserQuestion",
          "hooks": [ { "type": "process", "command": "bash",
            "args": ["~/.zcode/hooks/pomodoroIsland-notify.sh", "zcode", "ask-user-question"],
            "timeoutMs": 400000, "statusMessage": "等待岛屿上回答问题" } ] }
      ]
    }
  }
}
```

> 配置里 `~` 需写成绝对路径（如 `/Users/you/.zcode/hooks/...`）。

## 实现说明

- 阻塞模式读取 hook 事件的 stdin JSON（`tool_name` / `tool_input` / `reason` 等），转成 MCP `ask_user` 调用；需要系统安装 `python3`
- `permission-request` → `type=buttons`（允许/拒绝），返回 `hookSpecificOutput.decision`
- `ask-user-question` → 每题一次 `type=choice`（选项 label + description 作详情；单选附自定义输入），返回 `hookSpecificOutput.updatedInput`（原 questions + answers）并 `permissionDecision: allow`
- 日志：`/tmp/pomodoroIsland-notify.log`
- 调试环境变量：`POMODORO_ISLAND_ASK_TIMEOUT`（覆盖岛屿等待秒数）、`POMODORO_ISLAND_MCP_URL`（覆盖 MCP 地址）

## 手动测试

```bash
# 被动通知
bash ~/.zcode/hooks/pomodoroIsland-notify.sh zcode stop

# 权限请求（10 秒不点就回落）
echo '{"tool_name":"Bash","tool_input":{"command":"git push"},"reason":"Tool Bash requires approval"}' \
  | POMODORO_ISLAND_ASK_TIMEOUT=10 bash ~/.zcode/hooks/pomodoroIsland-notify.sh zcode permission-request

# AI 提问
echo '{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"用哪个库?","header":"Library","options":[{"label":"A","description":""},{"label":"B","description":""}]}]}}' \
  | POMODORO_ISLAND_ASK_TIMEOUT=10 bash ~/.zcode/hooks/pomodoroIsland-notify.sh zcode ask-user-question
```
