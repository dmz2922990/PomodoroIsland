import SwiftUI
import AppKit

/// 展开后的任务面板：主页面（计时+任务）与设置页二选一，内嵌切换
struct PanelView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: NotchWindowController

    @State private var showSettings = false
    @State private var newTaskTitle = ""
    @State private var hoveredTask: UUID?
    @State private var confirmingQuit = false
    @State private var quitConfirmWork: DispatchWorkItem?

    private var accent: Color { Theme.accent(for: engine.phase) }

    var body: some View {
        VStack(spacing: 0) {
            if showSettings {
                SettingsPage()
                    .transition(.opacity)
            } else {
                timerSection
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                divider

                taskList
                    .padding(.vertical, 8)

                addTaskField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            divider

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .animation(.easeInOut(duration: 0.15), value: showSettings)
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

    private var taskList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(openTasks) { task in
                    TaskRow(
                        task: task,
                        isCurrent: task.id == store.currentTaskId,
                        isHovered: hoveredTask == task.id,
                        onHover: { hovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoveredTask = hovering ? task.id : nil
                            }
                        },
                        onSelect: { store.setCurrent(task.id) },
                        onToggle: { store.toggleDone(task.id) },
                        onDelete: { store.deleteTask(task.id) }
                    )
                }

                if doneTasks.isEmpty == false {
                    HStack {
                        Text("已完成 \(doneTasks.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                    ForEach(doneTasks) { task in
                        TaskRow(
                            task: task,
                            isCurrent: false,
                            isHovered: hoveredTask == task.id,
                            onHover: { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    hoveredTask = hovering ? task.id : nil
                                }
                            },
                            onSelect: {},
                            onToggle: { store.toggleDone(task.id) },
                            onDelete: { store.deleteTask(task.id) }
                        )
                    }
                }

                if store.tasks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.textTertiary)
                        Text("还没有任务，先加一个吧")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 8)
        }
                    .frame(maxHeight: 232)
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
                system: showSettings ? "gearshape.fill" : "gearshape",
                help: showSettings ? "返回" : "设置"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSettings.toggle()
                }
            }

            quitButton
        }
    }
}

// MARK: - 设置页（内嵌，覆盖计时与任务区域）

private struct SettingsPage: View {

    @EnvironmentObject private var store: TaskStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("设置")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("点底部齿轮返回")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 2)

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

                SettingToggleRow(
                    title: "提示音",
                    isOn: store.settings.soundOn
                ) { on in update { $0.soundOn = on } }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func update(_ mutate: (inout AppSettings) -> Void) {
        var s = store.settings
        mutate(&s)
        store.updateSettings(s)
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
