# PomodoroIsland 🍅

住在 macOS 刘海里的番茄钟 + 任务管理器。

- **刘海岛屿**：收起时在刘海处显示紧凑倒计时；鼠标悬停（或点击）展开成任务面板
- **任务管理**：添加 / 完成 / 删除任务，点选当前任务，完成的番茄自动计入对应任务
- **番茄钟**：专注 / 小憩 / 长休息状态机，基于目标时间点计时（系统睡眠也能正确结算），支持暂停、跳过、重置
- **菜单栏常驻**：菜单栏实时显示倒计时，可快捷开始 / 暂停 / 退出
- **完成提醒**：系统通知 + 提示音
- **零依赖**：纯 Swift + SwiftUI/AppKit，Swift Package Manager 构建，不需要 Xcode 工程

## 环境要求

- macOS 13+
- Xcode Command Line Tools（`xcode-select --install`）

## 构建与运行

```bash
./scripts/make-app.sh
open build/PomodoroIsland.app
```

调试运行（不打包）：

```bash
swift run
```

## 使用

- 鼠标移到刘海停留片刻（或点击刘海）→ 展开面板
- 展开面板：`开始专注`；想换任务就点一下对应任务行
- 鼠标移开面板 → 自动收起
- 时长、自动休息、提示音：面板底部齿轮菜单

## 数据

任务与设置持久化在 `~/Library/Application Support/PomodoroIsland/store.json`。

## MCP 服务（AI 接入）

应用内嵌 MCP 服务（Streamable HTTP），接入的 AI（ZCode / Claude 等）可以直接增删改查任务、发送通知与交互提问、读取计时状态，界面实时同步。

📘 **详细使用方法与全部工具示例见 [docs/MCP.md](docs/MCP.md)**。

**接入**：设置页打开「MCP 服务」，复制地址，在 MCP 客户端配置中添加：

```json
{ "mcpServers": { "pomodoro-island": { "url": "http://127.0.0.1:9527/mcp" } } }
```

**工具**：

- 任务域：`list_tasks`（按 open/done/all 过滤）、`add_task`（标题+计划番茄数）、`update_task`（改名/勾选/计划量）、`delete_task`、`set_current_task`、`get_status`（阶段/剩余时间/今日番茄数）
- 通知域：`notify`（被动通知，岛屿自动弹出、自动消失）、`ask_user`（**阻塞式提问**：按钮 / 单选多选 / 文本输入，用户在岛屿上操作后返回结果，超时可设）、`list_notifications`（队列诊断）

**通知示例**：AI 调用 `ask_user` → 岛屿自动弹出选项卡片 → 你点了某个选项 → AI 收到 `{"status":"answered","selected":["休息一下"]}`。来源识别：初始化握手 `clientInfo.name` 或调用参数 `source`，卡片带来源徽标；单来源最多 2 条待响应、全局最多 3 条。

说明：仅监听本机 127.0.0.1；通过 MCP 完成当前任务同样会自动停止进行中的专注；新任务进入未完成列表末尾。

## 说明

交互与视觉思路参考了开源社区"刘海岛屿"类应用（如 CodeIsland、boring.notch 等）的通用做法，代码为独立实现，未复用任何第三方代码。
