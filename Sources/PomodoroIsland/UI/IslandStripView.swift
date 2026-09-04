import SwiftUI

/// 刘海条（岛屿本体）：顶部直角与屏幕顶融合，高度动态对齐当前屏幕的菜单栏
/// （刘海屏 = 物理刘海高度；外接屏 = 菜单栏高度）。收起时计时内容显示在
/// 刘海两侧的"翅膀"里，与刘海同高；展开时头部向下延伸出 44pt 的下巴。
struct IslandStripView: View {

    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var controller: NotchWindowController

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }

    /// 菜单栏/刘海高度带
    private var bandHeight: CGFloat {
        NotchScreenInfo.collapsedIslandHeight(on: screen)
    }

    private var totalHeight: CGFloat {
        bandHeight + (controller.isExpanded ? NotchScreenInfo.expandedExtension : 0)
    }

    /// 收起 = 刘海+翅膀宽度；展开 = 面板宽度
    private var islandWidth: CGFloat {
        controller.isExpanded
            ? NotchWindowController.panelWidth
            : NotchScreenInfo.collapsedIslandWidth(on: screen)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: controller.isExpanded ? 18 : 12,
            bottomTrailingRadius: controller.isExpanded ? 18 : 12,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Theme.islandColor)
                .overlay(shape.strokeBorder(Theme.cardBorder, lineWidth: 0.5))

            if controller.isExpanded {
                expandedHeader
                    .padding(.top, bandHeight + 6)
                    .transition(.opacity)
            } else {
                collapsedWings
                    .transition(.opacity)
            }
        }
        .frame(width: islandWidth, height: totalHeight)
        .contentShape(shape)
        .onTapGesture {
            // 展开态点岛屿头部收起（收起态由全局点击监听负责展开）
            if controller.isExpanded {
                controller.collapse()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.isExpanded)
    }

    // MARK: - 收起态（内容位于刘海两侧翅膀，与刘海同高）

    private var collapsedWings: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                phaseDot
                Text(engine.displayText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
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
        .frame(height: bandHeight)
        .animation(.easeInOut(duration: 0.15), value: engine.running)
    }

    private var phaseDot: some View {
        Circle()
            .fill(Theme.accent(for: engine.phase))
            .frame(width: 7, height: 7)
            .opacity(engine.running ? 1 : 0.55)
    }

    // MARK: - 展开态头部（位于刘海下方的 44pt 延伸区）

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.phase.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent(for: engine.phase))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(store.currentTask?.title ?? "未选择任务")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(engine.phase.label) · 今日 \(store.todayFocusCount) 🍅")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            Text(engine.displayText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .frame(height: NotchScreenInfo.expandedExtension - 8, alignment: .center)
    }
}
