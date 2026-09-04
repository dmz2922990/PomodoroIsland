import AppKit
import SwiftUI

/// 覆盖在刘海上的透明面板。
/// 设计要点：
/// - 无边框、不透明度为 0、无阴影，视觉上只有 SwiftUI 绘制的"岛屿"可见；
/// - nonactivatingPanel：交互时不抢走当前 App 的焦点（不打断用户打字）；
/// - 常驻所有空间、位置固定、层级高于菜单栏；
/// - 收起时 `ignoresMouseEvents = true` 完全穿透（不影响菜单栏/底层窗口），
///   展开时由 NotchWindowController 切回 false 以接收按钮点击。
final class NotchPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        alphaValue = 1

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        // 盖在菜单栏之上
        level = .statusBar

        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 透明区域点击穿透

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if let contentView = contentView, contentView.hitTest(event.locationInWindow) == nil {
                // 点击落在透明区域：转发给下层窗口，随后恢复接收事件
                let screenLocation = convertPoint(toScreen: event.locationInWindow)
                ignoresMouseEvents = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    Self.repost(event, at: screenLocation)
                    self?.ignoresMouseEvents = !(self?.isExpandedVisible ?? false)
                }
                return
            }
        }
        super.sendEvent(event)
    }

    /// 控制器展开状态（仅用于穿透恢复判断，由 Objective-C 关联或简单镜像）
    var isExpandedVisible = false

    private static func repost(_ event: NSEvent, at screenLocation: NSPoint) {
        guard let screen = NSScreen.main else { return }
        let point = CGPoint(x: screenLocation.x, y: screen.frame.height - screenLocation.y)
        let isLeft = event.type == .leftMouseDown
        let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: isLeft ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: isLeft ? .left : .right
        )
        cgEvent?.post(tap: .cghidEventTap)
    }
}
