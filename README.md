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

## 说明

交互与视觉思路参考了开源社区"刘海岛屿"类应用（如 CodeIsland、boring.notch 等）的通用做法，代码为独立实现，未复用任何第三方代码。
