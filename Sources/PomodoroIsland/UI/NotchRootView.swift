import SwiftUI

/// 刘海窗口的根视图：收起 = 翅膀岛屿；展开 = 从刘海一体向下延伸的大岛屿
struct NotchRootView: View {

    @EnvironmentObject private var controller: NotchWindowController

    var body: some View {
        ZStack(alignment: .top) {
            if controller.isExpanded {
                ExpandedIslandView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                    ))
            } else {
                IslandStripView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: controller.isExpanded)
    }
}

/// 展开态：头部（刘海下方延伸区）+ 任务面板融为一体的黑色岛屿，
/// 顶部直角贴屏幕顶，仅底部圆角。
struct ExpandedIslandView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }

    private var band: CGFloat {
        NotchScreenInfo.collapsedIslandHeight(on: screen)
    }

    private var totalHeight: CGFloat {
        band + NotchScreenInfo.expandedExtension + NotchWindowController.panelHeight
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 24,
            bottomTrailingRadius: 24,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Theme.islandColor)
                .overlay(shape.strokeBorder(Theme.cardBorder, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 5)

            VStack(spacing: 0) {
                // 顶部带：与刘海同高的区域（中心被物理刘海遮挡），留空
                Color.clear.frame(height: band + 6)

                expandedHeader
                    .frame(height: NotchScreenInfo.expandedExtension - 6)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.collapse() }

                PanelView()
            }
        }
        .frame(width: NotchWindowController.panelWidth, height: totalHeight)
        .contentShape(shape)
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            StatusIconView(
                phase: engine.phase,
                progress: engine.progress,
                isOvertime: engine.isOvertime,
                overtimeFraction: engine.overtimeFraction,
                size: 26
            )
            .frame(width: 30)

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
    }
}
