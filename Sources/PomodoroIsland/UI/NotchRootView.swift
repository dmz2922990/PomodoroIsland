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
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: notifications.pending.map(\.id))
    }
}

/// 展开态：头部（刘海下方延伸区）+ 任务面板融为一体的黑色岛屿，
/// 顶部直角贴屏幕顶，仅底部圆角。出现时高度从刘海带平滑生长。
struct ExpandedIslandView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var engine: PomodoroEngine
    @EnvironmentObject private var store: TaskStore

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }

    private var band: CGFloat {
        NotchScreenInfo.collapsedIslandHeight(on: screen)
    }

    private var fullHeight: CGFloat {
        band + NotchScreenInfo.expandedExtension + NotchWindowController.panelHeight
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
               height: fullHeight,
               alignment: .top)
        .background(
            // 阴影挂在圆角形状自身（矩形裁剪会把圆角挖空处也投上阴影）
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
            .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
        )
        .contentShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
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

/// 通知岛：刘海带 + 卡片堆叠（多 agent 并发时全部可见），高度随内容自适应
struct NotificationIslandView: View {

    @EnvironmentObject private var controller: NotchWindowController
    @EnvironmentObject private var notifications: NotificationStore

    private var screen: NSScreen { NotchScreenInfo.preferredScreen() }
    private var band: CGFloat { NotchScreenInfo.collapsedIslandHeight(on: screen) }

    /// 紧凑行（被动通知 / 溢出聚合行）的固定高度
    private static let compactRowHeight: CGFloat = 34
    /// 卡片间距
    private static let cardSpacing: CGFloat = 8
    /// 交互卡未实测前的估算高度
    private static let estimatedCardHeight: CGFloat = 300

    /// 堆叠可用高度预算（屏幕可视高扣除刘海带与底部边距）
    private var heightBudget: CGFloat {
        max(200, screen.visibleFrame.height - band - 24)
    }

    /// 渲染块：完整交互卡 / 被动紧凑行 / 溢出聚合行（放不下的卡片合并为一行）
    private enum StackBlock: Identifiable {
        case card(IslandNotification)
        case passiveRow(IslandNotification)
        case overflow([IslandNotification])

        var id: UUID {
            switch self {
            case .card(let n): return n.id
            case .passiveRow(let n): return n.id
            case .overflow(let list): return list.first?.id ?? UUID()
            }
        }
    }

    /// 单遍确定性决策：从上往下累计高度，放不下的卡片及以下全部折叠为一行「+N 排队」。
    /// 首块始终渲染（避免全部折叠的退化态）。交互卡只以完整形态渲染（保持其内部状态），
    /// 卡片高度用实测值（未实测时用估算，下一帧探针修正）。
    private var blocks: [StackBlock] {
        let order = notifications.displayOrder
        var result: [StackBlock] = []
        var used: CGFloat = 0
        var overflowed: [IslandNotification] = []

        for n in order {
            if !overflowed.isEmpty { overflowed.append(n); continue }
            let h = n.isInteractive
                ? (controller.cardHeights[n.id] ?? Self.estimatedCardHeight)
                : Self.compactRowHeight
            let isFirst = result.isEmpty
            if !isFirst, used + Self.cardSpacing + h > heightBudget {
                overflowed.append(n)
                continue
            }
            used += (isFirst ? 0 : Self.cardSpacing) + h
            result.append(n.isInteractive ? .card(n) : .passiveRow(n))
        }
        if !overflowed.isEmpty {
            result.append(.overflow(overflowed))
        }
        return result
    }

    private var displayHeight: CGFloat {
        band + 4 + controller.notificationContentHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // 刘海带（物理刘海不可见区）
            Color.clear.frame(height: band + 4)

            VStack(alignment: .leading, spacing: Self.cardSpacing) {
                ForEach(blocks) { block in
                    switch block {
                    case .card(let n):
                        NotificationCardView(notification: n, store: notifications)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                // 每张问题卡用橘黄色圆角边框包裹
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.orange, lineWidth: 1.2)
                            )
                            .background(HeightProbe(onChange: { h in
                                controller.cardHeightMeasured(n.id, h)
                            }))
                    case .passiveRow(let n):
                        PassiveNotificationRow(notification: n, store: notifications)
                    case .overflow(let list):
                        OverflowRow(count: list.count,
                                    first: list.first.map { "\($0.source) · \($0.title)" })
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .background(HeightProbe(onChange: { h in
                controller.notificationHeightChanged(h)
            }))
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
        // 高度不做弹簧动画：窗口 setFrame 是瞬时到位，视图高度若渐变会在切换瞬间被 .clipped() 拦腰截断
        .animation(nil, value: displayHeight)
    }
}

/// 被动通知紧凑行：来源点 + 标题（截断）+ 提前关闭；数秒后自动消失
private struct PassiveNotificationRow: View {
    let notification: IslandNotification
    let store: NotificationStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sourceDotColor(notification.source))
                .frame(width: 7, height: 7)

            Text(notification.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(notification.source)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)

            Button {
                store.respond(notification.id, NotificationResponse(status: "dismissed"))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("忽略")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

/// 溢出聚合行：屏高放不下的卡片合并显示
private struct OverflowRow: View {
    let count: Int
    let first: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            Text("还有 \(count) 条排队中")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let first {
                Text(first)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

/// 来源名哈希 → 稳定配色（与 NotificationCardView.sourceColor 同规则）
private func sourceDotColor(_ name: String) -> Color {
    var hash = 0
    for b in name.utf8 { hash = (hash &* 31 + Int(b)) & 0xFF }
    return Color(hue: Double(hash) / 255.0, saturation: 0.65, brightness: 0.85)
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
