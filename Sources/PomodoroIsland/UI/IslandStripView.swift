import SwiftUI

/// 收起态岛屿：高度动态对齐当前屏幕的菜单栏/刘海，单条带三段布局。
/// 左翼：状态像素图标；中央：当前任务标题（内置屏被物理刘海遮挡属设计预期，
/// 外接显示器可见）；右翼：圆形计时环（按轮次变色）。
/// （展开态由 ExpandedIslandView 负责）
struct IslandStripView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }

    /// 菜单栏/刘海高度带
    private var bandHeight: CGFloat {
        NotchScreenInfo.collapsedIslandHeight(on: screen)
    }

    private var islandWidth: CGFloat {
        NotchScreenInfo.collapsedIslandWidth(on: screen)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 12,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        content
            .frame(width: islandWidth, height: bandHeight)
            .background(shape.fill(Theme.islandColor))
            .background(shape.strokeBorder(Theme.cardBorder, lineWidth: 0.5))
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.15), value: engine.running)
    }

    // MARK: - 三段内容

    private var content: some View {
        HStack(spacing: 0) {
            // 左翼：状态图标
            StatusIconView(
                phase: engine.phase,
                progress: engine.progress,
                isOvertime: engine.isOvertime,
                overtimeFraction: engine.overtimeFraction,
                size: 18
            )
            .frame(width: NotchScreenInfo.collapsedWing - 4, alignment: .center)
            .frame(maxHeight: .infinity)

            // 中央：当前任务（刘海遮挡为预期设计）
            Group {
                if let task = store.currentTask {
                    Text(task.title)
                        .foregroundStyle(
                            engine.running
                                ? Color.white.opacity(0.92)   // 计时中：亮白
                                : Color.white.opacity(0.45)   // 待开始/暂停：灰色
                        )
                } else {
                    Text("未选择任务")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.system(size: 13.5, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: store.currentTask?.title)

            // 右翼：计时环
            RoundTimerBadge(
                progress: ringProgress,
                color: ringColor
            )
            .frame(width: NotchScreenInfo.collapsedWing - 4, alignment: .center)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 3)
    }

    // MARK: - 计时环状态

    /// 专注进行中的当天轮次（按按时完成的番茄数；超时的不计轮）
    private var focusRound: Int { store.todayOnTimeCount + 1 }

    private var ringColor: Color {
        if engine.isOvertime {
            return Color(red: 0.95, green: 0.30, blue: 0.25)
        }
        switch engine.phase {
        case .focus:
            // 第 1 轮白、第 2 轮黄、第 3 轮起一直红
            switch focusRound {
            case 1: return .white
            case 2: return Color(red: 1.0, green: 0.84, blue: 0.25)
            default: return Color(red: 0.95, green: 0.30, blue: 0.25)
            }
        case .shortBreak, .longBreak:
            return Theme.accent(for: engine.phase)
        case .idle:
            return Color.white.opacity(0.35)
        }
    }

    private var ringProgress: Double {
        switch engine.phase {
        case .focus, .shortBreak, .longBreak:
            return engine.isOvertime ? 1 : engine.progress
        case .idle:
            return 0
        }
    }
}

/// 圆形计时环：环的填充即计时进度
struct RoundTimerBadge: View {
    var progress: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .animation(.linear(duration: 0.4), value: progress)
    }
}
