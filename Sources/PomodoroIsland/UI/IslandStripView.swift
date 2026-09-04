import SwiftUI

/// 收起态岛屿：高度动态对齐当前屏幕的菜单栏/刘海，计时内容显示在
/// 刘海两侧的"翅膀"里，与刘海同高。（展开态由 ExpandedIslandView 负责）
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

    // MARK: - 翅膀内容（左侧状态+倒计时，右侧今日番茄数；中段是物理刘海留空）

    private var collapsedWings: some View {
        HStack(spacing: 6) {
            StatusIconView(
                phase: engine.phase,
                progress: engine.progress,
                isOvertime: engine.isOvertime,
                overtimeFraction: engine.overtimeFraction,
                size: 17
            )
            Text(engine.displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            .frame(width: NotchScreenInfo.collapsedWing - 12, alignment: .leading)
            .frame(maxHeight: .infinity)

            // 中段是物理刘海（不可显示），留空
            Spacer(minLength: 0)

            Group {
                if !engine.running, store.todayFocusCount > 0 {
                    Text("🍅×\(store.todayFocusCount)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: NotchScreenInfo.collapsedWing - 12, alignment: .trailing)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
    }
}
