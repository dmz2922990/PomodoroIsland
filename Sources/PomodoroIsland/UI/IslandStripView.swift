import SwiftUI

/// 收起态岛屿：高度动态对齐当前屏幕的菜单栏/刘海。
/// 左翼：状态像素图标（小苗/生长/腐烂）；右翼：圆形计时环（按轮次变色）。
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
        collapsedWings
            .frame(width: islandWidth, height: bandHeight)
            .background(shape.fill(Theme.islandColor))
            .background(shape.strokeBorder(Theme.cardBorder, lineWidth: 0.5))
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.15), value: engine.running)
    }

    // MARK: - 翅膀内容（左：状态图标；中：物理刘海留空；右：圆形计时环）

    private var collapsedWings: some View {
        HStack(spacing: 0) {
            StatusIconView(
                phase: engine.phase,
                progress: engine.progress,
                isOvertime: engine.isOvertime,
                overtimeFraction: engine.overtimeFraction,
                size: 18
            )
            .frame(width: NotchScreenInfo.collapsedWing - 6, alignment: .center)
            .frame(maxHeight: .infinity)

            // 中段是物理刘海（不可显示），留空
            Spacer(minLength: 0)

            RoundTimerBadge(
                progress: ringProgress,
                color: ringColor
            )
            .frame(width: NotchScreenInfo.collapsedWing - 6, alignment: .center)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 计时环的状态

    /// 专注进行中的当天轮次（第 1 轮 = 白，第 2 轮 = 黄，第 3 轮 = 红，之后循环）
    private var focusRound: Int { store.todayFocusCount + 1 }

    private var ringColor: Color {
        if engine.isOvertime {
            return Color(red: 0.95, green: 0.30, blue: 0.25)
        }
        switch engine.phase {
        case .focus:
            switch (focusRound - 1) % 3 {
            case 0: return .white
            case 1: return Color(red: 1.0, green: 0.84, blue: 0.25)
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
