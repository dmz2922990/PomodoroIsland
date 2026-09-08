import SwiftUI

/// 刘海窗口的根视图：收起 = 翅膀岛屿（专注中悬停垂降一行）；展开 = 任务面板 或 通知岛
struct NotchRootView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var notifications: NotificationStore

    var body: some View {
        ZStack(alignment: .top) {
            if controller.isExpanded {
                if notifications.current != nil {
                    NotificationIslandView()
                        .transition(.opacity)
                } else {
                    ExpandedIslandView()
                        .transition(.opacity)
                }
            } else {
                IslandStripView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: controller.isExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: notifications.current?.id)
    }
}

/// 展开态：头部（刘海下方延伸区）+ 任务面板融为一体的黑色岛屿，
/// 顶部直角贴屏幕顶，仅底部圆角。出现时高度从刘海带平滑生长。
struct ExpandedIslandView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore

    @State private var reveal: CGFloat = 0

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }

    private var band: CGFloat {
        NotchScreenInfo.collapsedIslandHeight(on: screen)
    }

    private var fullHeight: CGFloat {
        band + NotchScreenInfo.expandedExtension + NotchWindowController.panelHeight
    }

    private var displayHeight: CGFloat {
        band + (fullHeight - band) * reveal
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部带：与刘海同高的区域（中心被物理刘海遮挡），留空
            Color.clear.frame(height: band + 6)

            expandedHeader
                .frame(height: NotchScreenInfo.expandedExtension - 6)
                .contentShape(Rectangle())
                .onTapGesture { controller.collapse() }

            PanelView()
        }
        .frame(width: NotchWindowController.panelWidth,
               height: displayHeight,
               alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Theme.islandColor)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            )
        )
        .clipped()
        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
        .contentShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { reveal = 1 }
        }
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

    @State private var reveal: CGFloat = 0
    @State private var contentHeight: CGFloat = 120

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }
    private var band: CGFloat { NotchScreenInfo.collapsedIslandHeight(on: screen) }

    private var displayHeight: CGFloat {
        band + 4 + (contentHeight + 14) * reveal
    }

    var body: some View {
        VStack(spacing: 0) {
            // 刘海带（物理刘海不可见区）
            Color.clear.frame(height: band + 4)

            if let n = notifications.current {
                NotificationCardView(notification: n, store: notifications)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .background(HeightProbe(onChange: { h in
                        guard h != contentHeight else { return }
                        contentHeight = h
                        controller.notificationHeightChanged(h)
                    }))
            }
        }
        .frame(width: NotchWindowController.panelWidth,
               height: displayHeight,
               alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 20,
                bottomTrailingRadius: 20, topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Theme.islandColor)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0,
                    style: .continuous
                )
                .strokeBorder(Theme.cardBorder, lineWidth: 0.5)
            )
        )
        .clipped()
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { reveal = 1 }
        }
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
