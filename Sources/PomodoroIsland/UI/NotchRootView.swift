import SwiftUI

/// 刘海窗口的根视图：收起 = 翅膀岛屿；展开 = 任务面板 或 通知岛（仅有待处理通知时）
struct NotchRootView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var notifications: NotificationStore

    var body: some View {
        ZStack(alignment: .top) {
            if controller.isExpanded {
                if notifications.current != nil {
                    NotificationIslandView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity
                        ))
                } else {
                    ExpandedIslandView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity
                        ))
                }
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
    @EnvironmentObject private var notifications: NotificationStore

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
        HStack(spacing: 10) {
            StatusIconView(
                phase: engine.phase,
                progress: engine.progress,
                isOvertime: engine.isOvertime,
                overtimeFraction: engine.overtimeFraction,
                size: 40
            )
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentTask?.title ?? "未选择任务")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(engine.phase.label) · 今日 \(store.todayFocusCount) 🍅")
                    .font(.system(size: 11, weight: .medium))
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


/// 通知岛：刘海带 + 通知内容，高度随内容自适应，仅展示通知本身
struct NotificationIslandView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var notifications: NotificationStore

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }
    private var band: CGFloat { NotchScreenInfo.collapsedIslandHeight(on: screen) }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 20,
            bottomTrailingRadius: 20, topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Theme.islandColor)
                .overlay(shape.stroke(Theme.cardBorder, lineWidth: 0.5))

            VStack(spacing: 0) {
                // 刘海带（物理刘海不可见区）
                Color.clear.frame(height: band + 4)

                if let n = notifications.current {
                    NotificationCardView(notification: n, store: notifications)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .background(HeightProbe(onChange: { h in
                            controller.notificationHeightChanged(h)
                        }))
                }
            }
        }
        .frame(width: NotchWindowController.panelWidth)
    }
}

/// 内容高度探测器
private struct HeightProbe: View {
    var onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .task(id: geo.size.height) { onChange(geo.size.height) }
        }
    }
}
