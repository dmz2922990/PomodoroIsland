import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 任务列表分页
/// 面板页面
private enum PanelPage {
    case main, settings, notifications
}

private enum TaskTab {
    case open
    case done
}

/// 设置页分页
private enum SettingsTab {
    case timer
    case general
}

/// 展开后的任务面板：主页面（计时+任务）与设置页二选一，内嵌切换
struct PanelView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var notifications: NotificationStore

    @State private var page: PanelPage = .main
    @State private var newTaskTitle = ""
    @State private var hoveredTask: UUID?
    @State private var confirmingQuit = false
    @State private var quitConfirmWork: DispatchWorkItem?
    @State private var taskTab: TaskTab = .open
    @State private var draggingTaskId: UUID?

    private var accent: Color { Theme.accent(for: engine.phase) }

    var body: some View {
        VStack(spacing: 0) {
            if page == .settings {
                SettingsPage()
                    .transition(.opacity)
            } else if page == .notifications {
                NotificationHistoryPage()
                    .transition(.opacity)
            } else {
                timerSection
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                divider

                taskTabs
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                taskList
                    .padding(.top, 6)

                addTaskField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            divider

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .animation(.easeInOut(duration: 0.15), value: page)
        .frame(width: NotchWindowController.panelWidth,
               height: NotchWindowController.panelHeight,
               alignment: .top)
    }

    // MARK: - 计时区

    private var timerSection: some View {
        VStack(spacing: 8) {
            Text(engine.displayText)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .contentTransition(.numericText())
                .animation(.default, value: engine.displayText)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: max(4, geo.size.width * engine.progress))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 52)

            Text(phaseSubtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
    }

    private var phaseSubtitle: String {
        switch engine.phase {
        case .idle:
            return "下一个专注 \(store.settings.focusMinutes) 分钟 · 悬停刘海开始"
        default:
            if engine.isOvertime {
                return "超时中 · 番茄在腐烂，快休息 🍂"
            }
            return engine.running ? "保持节奏，别分心 💪" : "已暂停"
        }
    }

    // MARK: - 控制区

    private var controls: some View {
        HStack(spacing: 10) {
            primaryButton

            IconButton(system: "arrowshape.right.fill", help: "跳过当前阶段") {
                engine.skip()
            }
            IconButton(system: "arrow.counterclockwise", help: "重置计时") {
                engine.reset()
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch (engine.phase, engine.running) {
        case (.idle, _):
            ActionButton(title: "开始专注", accent: Theme.accent(for: .focus)) {
                engine.startFocus()
            }
        case (_, true):
            ActionButton(title: "暂停", accent: accent, filled: false) {
                engine.togglePause()
            }
        case (_, false):
            ActionButton(title: "继续", accent: accent) {
                engine.togglePause()
            }
        }
    }

    // MARK: - 任务列表

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    private var openTasks: [TaskItem] { store.tasks.filter { !$0.isDone } }
    private var doneTasks: [TaskItem] { store.tasks.filter { $0.isDone } }
    private var visibleTasks: [TaskItem] { taskTab == .open ? openTasks : doneTasks }

    // MARK: - 任务分页

    private var taskTabs: some View {
        HStack(spacing: 4) {
            CapsuleSegmentButton(title: "未完成", count: openTasks.count, selected: taskTab == .open) {
                withAnimation(.easeInOut(duration: 0.15)) { taskTab = .open }
            }
            CapsuleSegmentButton(title: "已完成", count: doneTasks.count, selected: taskTab == .done) {
                withAnimation(.easeInOut(duration: 0.15)) { taskTab = .done }
            }
            Spacer()
        }
    }


    private var taskList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(visibleTasks) { task in
                    TaskRow(
                        task: task,
                        isCurrent: taskTab == .open && task.id == store.currentTaskId,
                        isHovered: hoveredTask == task.id,
                        onHover: { hovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoveredTask = hovering ? task.id : nil
                            }
                        },
                        onSelect: taskTab == .open ? { store.setCurrent(task.id) } : {},
                        onToggle: { store.toggleDone(task.id) },
                        onDelete: { store.deleteTask(task.id) }
                    )
                    .opacity(draggingTaskId == task.id ? 0.45 : 1)
                    .onDrag {
                        draggingTaskId = task.id
                        return NSItemProvider(object: task.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TaskDropDelegate(
                        rowId: task.id,
                        tab: taskTab,
                        store: store,
                        draggingTaskId: $draggingTaskId
                    ))
                }

                emptyState
            }
            .padding(.horizontal, 8)
        }
        .frame(maxHeight: 232)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.tasks.isEmpty {
            emptyPlaceholder(icon: "list.clipboard", text: "还没有任务，先加一个吧")
        } else if taskTab == .open && openTasks.isEmpty {
            emptyPlaceholder(icon: "checkmark.seal", text: "都完成啦，休息一下 🎉")
        } else if taskTab == .done && doneTasks.isEmpty {
            emptyPlaceholder(icon: "tray", text: "还没有已完成的任务")
        }
    }

    private func emptyPlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 退出（两步确认，防止误触）

    private var quitButton: some View {
        Button {
            if confirmingQuit {
                quitConfirmWork?.cancel()
                NSApp.terminate(nil)
            } else {
                confirmingQuit = true
                let work = DispatchWorkItem { confirmingQuit = false }
                quitConfirmWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
            }
        } label: {
            Group {
                if confirmingQuit {
                    Text("确认退出")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(
                            Capsule().fill(Color(red: 0.92, green: 0.32, blue: 0.30))
                        )
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("退出")
        .animation(.easeInOut(duration: 0.15), value: confirmingQuit)
    }

    // MARK: - 输入区

    private var addTaskField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            TextField("新任务，回车添加", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .onSubmit {
                    store.addTask(title: newTaskTitle)
                    newTaskTitle = ""
                }

            if !newTaskTitle.isEmpty {
                Button {
                    store.addTask(title: newTaskTitle)
                    newTaskTitle = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 4) {
            Text("今日 \(store.todayFocusCount) 🍅")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            IconButton(
                system: page == .settings ? "gearshape.fill" : "gearshape",
                help: page == .settings ? "返回" : "设置"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    page = page == .settings ? .main : .settings
                }
            }

            ZStack(alignment: .topTrailing) {
                IconButton(
                    system: page == .notifications ? "bell.fill" : "bell",
                    help: page == .notifications ? "返回" : "通知"
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        page = page == .notifications ? .main : .notifications
                    }
                }
                if !notifications.pending.isEmpty {
                    Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 2, y: 1)
                }
            }

            quitButton
        }
    }
}

// MARK: - 设置页（内嵌，覆盖计时与任务区域）

private struct SettingsPage: View {

    @EnvironmentObject private var store: TaskStore
    @State private var settingsTab: SettingsTab = .timer

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 4) {
                    CapsuleSegmentButton(title: "计时", selected: settingsTab == .timer) {
                        withAnimation(.easeInOut(duration: 0.15)) { settingsTab = .timer }
                    }
                    CapsuleSegmentButton(title: "通用", selected: settingsTab == .general) {
                        withAnimation(.easeInOut(duration: 0.15)) { settingsTab = .general }
                    }
                    Spacer()
                    Text("点底部齿轮返回")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 2)

                if settingsTab == .timer {
                    VStack(spacing: 16) {
                        DurationChipsRow(
                            title: "专注时长",
                            values: [15, 20, 25, 30, 45, 50, 60],
                            selection: store.settings.focusMinutes
                        ) { v in update { $0.focusMinutes = v } }

                        DurationChipsRow(
                            title: "小憩时长",
                            values: [3, 5, 10],
                            selection: store.settings.shortBreakMinutes
                        ) { v in update { $0.shortBreakMinutes = v } }

                        DurationChipsRow(
                            title: "长休息时长",
                            values: [10, 15, 20, 30],
                            selection: store.settings.longBreakMinutes
                        ) { v in update { $0.longBreakMinutes = v } }

                        DurationChipsRow(
                            title: "几轮专注后长休息",
                            values: [2, 3, 4, 6],
                            selection: store.settings.longBreakEvery
                        ) { v in update { $0.longBreakEvery = v } }

                        SettingToggleRow(
                            title: "结束后自动开始休息",
                            isOn: store.settings.autoStartBreak
                        ) { on in update { $0.autoStartBreak = on } }
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: 14) {
                        SettingToggleRow(
                            title: "通知服务（AI 发通知/提问）",
                            isOn: store.settings.notifyEnabled
                        ) { on in update { $0.notifyEnabled = on } }

                        SettingToggleRow(
                            title: "通知到达时自动弹出",
                            isOn: store.settings.notifyAutoExpand
                        ) { on in update { $0.notifyAutoExpand = on } }

                        SettingToggleRow(
                            title: "提示音",
                            isOn: store.settings.soundOn
                        ) { on in update { $0.soundOn = on } }

                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)

                        mcpSection
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.15), value: settingsTab)
    }

    private func update(_ mutate: (inout AppSettings) -> Void) {
        var s = store.settings
        mutate(&s)
        store.updateSettings(s)
    }

    // MARK: MCP 服务区

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 与 SettingToggleRow 同构：标题（+状态）居左，开关贴最右
            HStack {
                Text("MCP 服务")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                Text(store.mcpStatusText.isEmpty ? " " : store.mcpStatusText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(store.mcpStatusText == "运行中"
                                     ? Color(red: 0.35, green: 0.78, blue: 0.44)
                                     : Theme.textTertiary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { store.settings.mcpEnabled },
                    set: { on in update { $0.mcpEnabled = on } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Text("供接入的 AI（ZCode / Claude 等）增删改查任务、读取计时状态")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 6) {
                Text("http://127.0.0.1:\(String(store.settings.mcpPort))/mcp")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("http://127.0.0.1:\(store.settings.mcpPort)/mcp", forType: .string)
                } label: {
                    Text("复制")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 时长选择行：一排胶囊选项，选中高亮
private struct DurationChipsRow: View {
    let title: String
    let values: [Int]
    let selection: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { v in
                    chip(v)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ v: Int) -> some View {
        let selected = v == selection
        return Button {
            onChange(v)
        } label: {
            Text("\(v)")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.black : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule().fill(selected ? Theme.accent(for: .focus) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

/// 开关行
private struct SettingToggleRow: View {
    let title: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity)
    }
}

/// 拖拽排序代理：拖动行进入目标行时实时重排（同分页内移动）
private struct TaskDropDelegate: DropDelegate {
    let rowId: UUID
    let tab: TaskTab
    let store: TaskStore
    @Binding var draggingTaskId: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingId = draggingTaskId, draggingId != rowId else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.moveTask(
                inDoneList: tab == .done,
                fromId: draggingId,
                toId: rowId
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingTaskId = nil
        return true
    }
}

/// 单条任务
struct TaskRow: View {
    let task: TaskItem
    let isCurrent: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        task.isDone
                            ? Color(red: 0.35, green: 0.78, blue: 0.44)
                            : Theme.textTertiary
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .strikethrough(task.isDone, color: Theme.textTertiary)
                    .foregroundStyle(task.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 4)

            if isCurrent && !task.isDone {
                Text("当前")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent(for: .focus).opacity(0.9)))
            }

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in onHover(hovering) }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append("🍅 \(task.pomosDone)")
        if let planned = task.pomosPlanned {
            parts[0] = "🍅 \(task.pomosDone)/\(planned)"
        }
        let df = RelativeDateTimeFormatter()
        df.locale = Locale(identifier: "zh_CN")
        parts.append(df.localizedString(for: task.createdAt, relativeTo: Date()) + "创建")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 子组件

/// 圆形小图标按钮
struct IconButton: View {
    let system: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.white.opacity(0.07))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// 主操作按钮
struct ActionButton: View {
    let title: String
    let accent: Color
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(filled ? Color.black : accent)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    Capsule().fill(filled ? accent : accent.opacity(0.16))
                )
                .overlay(
                    Capsule().strokeBorder(accent.opacity(filled ? 0 : 0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// 胶囊分段按钮（任务 Tab / 设置 Tab 共用）
private struct CapsuleSegmentButton: View {
    let title: String
    var count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0.07)))
                }
            }
            .font(.system(size: 11.5, weight: selected ? .bold : .medium))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.12 : 0.00)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}

/// 通知中心页：待处理 + 历史记录（最近 20 条，内存）
private struct NotificationHistoryPage: View {

    @EnvironmentObject private var notifications: NotificationStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("通知")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if !notifications.pending.isEmpty || !notifications.history.isEmpty {
                        Button {
                            notifications.clearAll()
                        } label: {
                            Text("清空")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("点底部铃铛返回")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 2)

                if !notifications.pending.isEmpty {
                    sectionHeader("待处理", count: notifications.pending.count)
                    ForEach(notifications.pending) { n in
                        row(n)
                    }
                }

                if !notifications.history.isEmpty {
                    sectionHeader("历史", count: notifications.history.count)
                    ForEach(notifications.history) { n in
                        row(n)
                    }
                }

                if notifications.pending.isEmpty && notifications.history.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.textTertiary)
                        Text("暂无通知")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
            Text("\(count)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
    }

    private func row(_ n: IslandNotification) -> some View {
        let (stateText, stateColor) = stateBadge(n)
        return HStack(spacing: 9) {
            Circle()
                .fill(n.kind.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(n.source)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Text(n.kind.label)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(n.kind.color)
                }
                Text(n.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !n.message.isEmpty {
                    Text(n.message)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(stateText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                Text(relativeTime(n.respondedAt ?? n.creation))
                    .font(.system(size: 8.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func stateBadge(_ n: IslandNotification) -> (String, Color) {
        guard let r = n.response else { return ("等待中", n.kind.color) }
        switch r.status {
        case "answered":
            if let c = r.clicked { return ("已点 · \(c)", Color(red: 0.35, green: 0.78, blue: 0.44)) }
            if !r.selected.isEmpty {
                return r.selected.count == 1
                    ? ("已选 · \(r.selected[0])", Color(red: 0.35, green: 0.78, blue: 0.44))
                    : ("已选 \(r.selected.count) 项", Color(red: 0.35, green: 0.78, blue: 0.44))
            }
            if let t = r.text { return ("已回复 · \(t)", Color(red: 0.35, green: 0.78, blue: 0.44)) }
            return ("已回答", Color(red: 0.35, green: 0.78, blue: 0.44))
        case "timeout":
            return ("超时未答", Color(red: 1.0, green: 0.84, blue: 0.25))
        default:
            return ("已忽略", Theme.textTertiary)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let df = RelativeDateTimeFormatter()
        df.locale = Locale(identifier: "zh_CN")
        return df.localizedString(for: date, relativeTo: Date())
    }
}
