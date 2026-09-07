import AppKit
import SwiftUI
import Combine

/// 通知独立岛屿窗口：悬浮在主岛屿正下方，有待处理通知时显示，全部结算后隐藏。
/// 与主岛屿互不干扰——主岛屿保持"点击展开/移出收起"的自然行为。
final class NotificationWindowController {

    static let width: CGFloat = 380
    static let height: CGFloat = 380
    /// 与收起态主岛屿的间距
    static let gapBelowIsland: CGFloat = 6

    private var window: NotchPanel?
    private let notifications: NotificationStore
    /// 是否允许弹出展示（对应设置「通知到达时自动弹出」）
    var showWhen: (() -> Bool)?
    private var cancellable: Any?
    private var isVisible = false

    init(notifications: NotificationStore) {
        self.notifications = notifications
    }

    func start() {
        let screen = NotchScreenInfo.preferredScreen()
        let panel = NotchPanel(contentRect: frame(on: screen))
        panel.contentView = NSHostingView(
            rootView: NotificationCardContainer().environmentObject(notifications)
        )
        // 通知窗口常驻可交互（透明区域穿透由 NotchPanel.sendEvent 处理）
        panel.staysInteractive = true
        window = panel

        cancellable = notifications.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func shutdown() {
        cancellable = nil
        window?.close()
        window = nil
    }

    private func refresh() {
        guard let window else { return }
        if notifications.current != nil, showWhen?() != false {
            let screen = NotchScreenInfo.preferredScreen()
            window.setFrame(frame(on: screen), display: true)
            if !isVisible {
                isVisible = true
                window.orderFrontRegardless()
            }
        } else if isVisible {
            isVisible = false
            window.orderOut(nil)
        }
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let band = NotchScreenInfo.collapsedIslandHeight(on: screen)
        let frame = screen.frame
        return NSRect(
            x: frame.midX - Self.width / 2,
            y: frame.maxY - band - Self.gapBelowIsland - Self.height,
            width: Self.width,
            height: Self.height
        )
    }
}

/// 通知窗口根视图：最新一条通知卡片，顶部对齐
struct NotificationCardContainer: View {

    @EnvironmentObject private var notifications: NotificationStore

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            if let n = notifications.current {
                NotificationCardView(notification: n, store: notifications)
                    .frame(width: NotificationWindowController.width - 20)
                    .padding(.top, 0)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: notifications.current?.id)
    }
}
