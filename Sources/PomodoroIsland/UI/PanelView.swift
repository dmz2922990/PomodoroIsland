import SwiftUI
import AppKit

/// 展开后的任务面板
struct PanelView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: NotchWindowController

    @State private var newTaskTitle = ""
    @State private var hoveredTask: UUID?

    private var accent: Color { Theme.accent(for: engine.phase) }

    var body: some View {
        VStack(spacing: 0) {
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

            divider

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
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
            let focus = store.settings.focusMinutes
            let willBreak = engine.running ? "" : nextActionHint
            return "下一个专注 \(focus) 分钟 · \(willBreak)"
        default:
            if engine.isOvertime {
                return "超时中 · 番茄在腐烂，快休息 🍂"
            }
            return engine.running ? "保持节奏，别分心 💪" : "已暂停"
        }
    }

    private var nextActionHint: String {
        "悬停刘海开始"
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

            SettingsMenuView()

            IconButton(system: "xmark.circle", help: "退出 PomodoroIsland") {
                NSApp.terminate(nil)
            }
        }
    }
}

/// 设置菜单：独立子视图，只依赖 store。
/// 计时引擎每秒刷新会重建 PanelView，但本视图输入不变会被 SwiftUI 跳过，
/// 从而避免打开中的 NSMenu 被反复重建导致二级菜单闪烁。
private struct SettingsMenuView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        Menu {
            Menu("专注时长") {
                ForEach([15, 20, 25, 30, 45, 50, 60], id: \.self) { m in
                    Button("\(m) 分钟") {
                        update { $0.focusMinutes = m }
                    }
                }
            }
            Menu("小憩时长") {
                ForEach([3, 5, 10], id: \.self) { m in
                    Button("\(m) 分钟") {
                        update { $0.shortBreakMinutes = m }
                    }
                }
            }
            Menu("长休息时长") {
                ForEach([10, 15, 20, 30], id: \.self) { m in
                    Button("\(m) 分钟") {
                        update { $0.longBreakMinutes = m }
                    }
                }
            }
            Toggle("结束后自动开始休息", isOn: Binding(
                get: { store.settings.autoStartBreak },
                set: { on in update { $0.autoStartBreak = on } }
            ))
            Toggle("提示音", isOn: Binding(
                get: { store.settings.soundOn },
                set: { on in update { $0.soundOn = on } }
            ))
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("设置")
    }

    private func update(_ mutate: (inout AppSettings) -> Void) {
        var s = store.settings
        mutate(&s)
        store.updateSettings(s)
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
