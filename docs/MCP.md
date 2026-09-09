# PomodoroIsland MCP 使用说明

PomodoroIsland 内嵌一个 MCP（Model Context Protocol）服务，让接入的 AI 客户端（ZCode、Claude、Cursor 等）能够：

- **管理任务**：增删改查、设定当前任务、计划番茄数
- **发送通知**：被动通知（自动消失）与交互式提问（按钮 / 选项 / 输入框），用户在刘海岛屿上直接作答
- **读取状态**：专注阶段、剩余时间、今日番茄数

界面与数据实时同步——AI 的任何操作立即反映在刘海岛屿上。

## 接入方式

1. 启动 PomodoroIsland
2. 展开岛屿 → 点击底部**齿轮** → 「通用」Tab → 确认 **MCP 服务**开关已打开（绿色"运行中"）
3. 点击**复制**按钮复制服务地址（默认 `http://127.0.0.1:9527/mcp`）
4. 在 MCP 客户端中添加服务，例如 ZCode / Claude Desktop 的配置：

```json
{
  "mcpServers": {
    "pomodoro-island": {
      "url": "http://127.0.0.1:9527/mcp"
    }
  }
}
```

重启客户端后即可使用。

> 端口可在设置页修改（1024-65535）；服务仅监听本机 127.0.0.1，不对外网暴露。

## 快速上手（curl 实测）

服务是标准 JSON-RPC 2.0 over HTTP，用 curl 就能直接调试。以下命令均可直接复制执行。

**① 握手（initialize），记录返回的 `MCP-Session-Id` 响应头（后续可带上作为来源身份）：**

```bash
curl -s -i -X POST http://127.0.0.1:9527/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"我的工具","version":"1.0"}}}'
```

响应：

```json
{"result":{"capabilities":{"tools":{}},"protocolVersion":"2025-06-18","serverInfo":{"name":"pomodoro-island","version":"1.2.0"}},"jsonrpc":"2.0","id":1}
```

**② 列出全部工具：**

```bash
curl -s -X POST http://127.0.0.1:9527/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

**③ 发一条被动通知（岛屿立即弹出，8 秒消失）：**

```bash
curl -s -X POST http://127.0.0.1:9527/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"notify","arguments":{"title":"🔔 结算流程复测","message":"10 秒后消失，观察是否直接缩回刘海条、不再闪任务面板","level":"success","autoDismiss":10,"source":"ZCode"}}}'
```

**④ 查询今日状态：**

```bash
curl -s -X POST http://127.0.0.1:9527/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_status","arguments":{}}}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['content'][0]['text'])"
```

输出：

```json
{
  "currentTask" : "写周报",
  "displayTime" : "24:57",
  "phase" : "focus",
  "remainingSeconds" : 1497,
  "running" : true,
  "todayFocusCount" : 3
}
```

以下示例统一使用这个 helper 简化书写：

```bash
MCP=http://127.0.0.1:9527/mcp
call() { curl -s -X POST $MCP -H 'Content-Type: application/json' -d "$1"; }
```

---

## 工具总览（9 个）

| 工具 | 域 | 阻塞 | 说明 |
|---|---|---|---|
| `list_tasks` | 任务 | 否 | 列出任务，可按状态过滤 |
| `add_task` | 任务 | 否 | 新增任务 |
| `update_task` | 任务 | 否 | 改名 / 勾选完成 / 设计划番茄数 |
| `delete_task` | 任务 | 否 | 删除任务 |
| `set_current_task` | 任务 | 否 | 指定当前任务 |
| `get_status` | 状态 | 否 | 专注阶段、剩余时间、今日番茄数 |
| `notify` | 通知 | 否 | 发送被动通知（自动消失） |
| `ask_user` | 通知 | **是** | 向用户提问并等待其在岛屿上作答 |
| `list_notifications` | 通知 | 否 | 通知队列诊断（待响应 / 历史） |

---

## 任务域工具

### list_tasks

```bash
call '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"list_tasks","arguments":{"filter":"open"}}}'
```

- `filter`：`open`（未完成，默认 all 之外的常用值）/ `done` / `all`
- 返回任务数组，字段：`id`、`title`、`isDone`、`pomosDone`、`pomosPlanned`、`isCurrent`、`createdAt`

响应示例（节选）：

```json
{
  "count": 2,
  "tasks": [
    {"id": "E9F3C075-...", "title": "写周报", "isDone": false,
     "pomosDone": 2, "pomosPlanned": 4, "isCurrent": true,
     "createdAt": "2026-09-08T02:00:00Z"}
  ]
}
```

### add_task

```bash
call '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"add_task","arguments":{"title":"复习 MCP 文档","planned":2}}}'
```

- `title`（必填）：任务标题
- `planned`（可选）：计划番茄数
- 新任务进入**未完成列表末尾**；返回新任务对象（含 `id`）

### update_task

```bash
ID="E9F3C075-C39E-403D-A62F-50C063F01578"   # 来自 list_tasks
call "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"update_task\",\"arguments\":{\"id\":\"$ID\",\"isDone\":true}}}"
```

- `id`（必填）：任务 id（来自 `list_tasks`）
- `title` / `isDone` / `planned`：至少提供一个
- 注意：**完成当前任务会自动停止进行中的专注**（该番茄不计入）

### delete_task

```bash
call "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"delete_task\",\"arguments\":{\"id\":\"$ID\"}}}"
```

### set_current_task

```bash
call "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"set_current_task\",\"arguments\":{\"id\":\"$ID\"}}}"
```

- 仅未完成任务可设为当前；之后完成的番茄计入该任务

---

## 通知域工具

### notify（被动通知，非阻塞）

```bash
call '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"notify","arguments":{"title":"部署完成","message":"生产环境已更新到 v1.2.0","level":"success","autoDismiss":8,"source":"DeployBot"}}}'
```

响应：

```json
{"result":{"content":[{"text":"{\n  \"autoDismiss\" : 8,\n  \"id\" : \"C5D24F06-...\",\n  \"source\" : \"DeployBot\"\n}","type":"text"}],"isError":false},"jsonrpc":"2.0","id":20}
```

- `title`（必填）；`level`：`info` / `success` / `warning` / `error`（四种配色）
- `autoDismiss`：自动消失秒数，默认 8，范围 2-300
- 立即返回 `{"id": "...", "source": "DeployBot", "autoDismiss": 8}`
- 岛屿自动弹出展示，到时自动消失；来源徽标色点由来源名哈希生成

### ask_user（交互提问，阻塞）

工具调用会**阻塞**直到用户在岛屿上作答或超时。三种交互类型：

**① 按钮（buttons）**——2-4 个按钮：

```bash
# 阻塞直到用户在岛屿上点击按钮（或 120 秒超时）
call '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"ask_user","arguments":{"title":"部署确认","message":"即将发布到生产环境","type":"buttons","buttons":["立即发布","取消"],"timeoutSeconds":120,"source":"DeployBot"}}}'
```

用户点击"立即发布"后，curl 返回：

```json
{"result":{"content":[{"text":"{\n  \"status\" : \"answered\",\n  \"clicked\" : \"立即发布\",\n  \"source\" : \"DeployBot\"\n}","type":"text"}],"isError":false},"jsonrpc":"2.0","id":21}
```

**② 选项（choice）**——2-6 个选项，支持说明文字、多选、自定义输入：

```bash
call '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"ask_user","arguments":{"title":"今晚吃什么？","type":"choice","options":[{"label":"麦当劳","detail":"1+1 真香"},{"label":"沙县小吃","detail":"经济实惠"}],"allowInput":true,"multiSelect":false,"timeoutSeconds":300}}}'
```

- 单选：点击选项立即返回 `{"status": "answered", "selected": ["麦当劳"]}`
- 多选（`multiSelect: true`）：勾选后点提交，返回所有选中 label
- `allowInput: true`：选项下方附输入框，自定义回答返回 `{"status": "answered", "text": "吃火锅"}`

**③ 输入（input）**——纯文本输入：

```bash
call '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"ask_user","arguments":{"title":"给本轮专注起个名字","type":"input","placeholder":"例如：重构登录模块","timeoutSeconds":120}}}'
```

返回 `{"status": "answered", "text": "重构登录模块"}`

**超时与取消**：

- `timeoutSeconds` 默认 120，范围 5-600；超时返回 `{"status": "timeout"}`，用户点 ✕ 返回 `{"status": "dismissed"}`
- 阻塞期间岛屿保持展开，不会被鼠标移出收起

**来源识别**：`source` 参数标识发送方（如 `"DeployBot"`）；未提供时使用 MCP 握手的 `clientInfo.name`。卡片显示来源徽标（哈希稳定配色）。

**并发限制**：同一来源最多 2 条待响应提问、全局最多 3 条，超出返回错误；被动通知最多 5 条（超出挤掉最旧）。

**多通知展示**：多条待处理时岛屿纵向堆叠显示——交互式提问卡（橘黄色圆角边框包裹）先到在前、每张可直接作答；被动通知折叠为底部紧凑行。新通知不再抢占正在等待回答的卡片。屏高放不下时末尾折叠为「+N 条排队中」一行。

### list_notifications（诊断）

```json
{"name": "list_notifications", "arguments": {}}
```

返回待响应队列与最近历史的简报（id / source / kind / title / state），用于排查"提问是否送达、是否超时"。

---

## 完整对话示例

> Agent：今天有哪些没做完的任务？
>
> （调用 `list_tasks {"filter": "open"}` → 读到 3 条）
>
> Agent：要不要先专注「写周报」？我先把它设为当前任务并开始提醒。
>
> （调用 `set_current_task`）
>
> Agent：写完了告诉我一声，我来勾掉它。
>
> 用户：写完了。
>
> Agent：（调用 `update_task {"id": "...", "isDone": true}`，然后 `get_status` 确认今日番茄数）
>
> Agent：已勾掉 ✅ 今天完成了 3 个番茄。要不要休息 15 分钟？

## 错误响应示例

工具级错误（如任务不存在、缺参数、超上限）通过 `isError: true` 返回：

```json
{"result":{"content":[{"text":"来源「DeployBot」已有 2 条待响应通知，请先等待处理","type":"text"}],"isError":true},"jsonrpc":"2.0","id":30}
```

协议级错误（如未知方法）走 JSON-RPC error 字段：

```json
{"jsonrpc":"2.0","id":31,"error":{"code":-32601,"message":"method not found: xxx"}}
```

## 注意事项

- 通知服务可在设置页整体关闭；关闭后 `notify` / `ask_user` 返回错误
- 通过 MCP 完成当前任务与手动勾选行为一致：会自动停止进行中的专注
- 待响应提问超时返回 `timeout`，不算用户的回答；番茄计时不受通知影响
- 历史通知保留最近 20 条，持久化在 `~/Library/Application Support/PomodoroIsland/notifications.json`
