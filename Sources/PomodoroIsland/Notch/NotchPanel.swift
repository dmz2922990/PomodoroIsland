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
}
