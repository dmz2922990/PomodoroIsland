import AppKit

/// 屏幕刘海区域的几何信息。
/// 全部使用 AppKit 公开 API；带物理刘海的屏幕用 safeAreaInsets 精确计算，
/// 没有刘海的屏幕（外接显示器 / 旧机型）则按典型刘海尺寸画一个"虚拟刘海"。
enum NotchScreenInfo {

    /// 典型 MacBook 刘海的近似尺寸（无真实刘海时使用）
    static let fallbackSize = CGSize(width: 200, height: 32)

    /// 收起状态下刘海向下延伸的"下巴"高度（计时内容显示区，物理刘海本身无法显示像素）
    static let collapsedExtension: CGFloat = 24
    /// 展开状态下岛屿头部的延伸高度
    static let expandedExtension: CGFloat = 44

    /// 岛屿矩形：刘海区域 + 向下延伸。屏幕坐标系（左下原点），顶边贴屏幕顶。
    static func islandRect(on screen: NSScreen, expanded: Bool) -> NSRect {
        let strip = stripRect(on: screen)
        let ext = expanded ? expandedExtension : collapsedExtension
        return NSRect(
            x: strip.minX,
            y: strip.minY - ext,
            width: strip.width,
            height: strip.height + ext
        )
    }

    /// 优先返回带刘海的内置屏幕，否则主屏幕
    static func preferredScreen() -> NSScreen {
        if let builtin = NSScreen.screens.first(where: { $0.hasPhysicalNotch }) {
            return builtin
        }
        if let builtin = NSScreen.screens.first(where: { $0.isBuiltin }) {
            return builtin
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// 刘海条（收起状态岛屿占据的矩形），屏幕坐标系（左下原点）
    static func stripRect(on screen: NSScreen) -> NSRect {
        let size = notchSize(on: screen)
        let frame = screen.frame
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// 刘海尺寸
    static func notchSize(on screen: NSScreen) -> CGSize {
        if #available(macOS 12.0, *) {
            let topInset = screen.safeAreaInsets.top
            if topInset > 0 {
                let left = screen.auxiliaryTopLeftArea?.width ?? 0
                let right = screen.auxiliaryTopRightArea?.width ?? 0
                if left > 0, right > 0 {
                    // 屏幕总宽 - 两侧安全区 = 相机开窗宽度
                    let width = screen.frame.width - left - right
                    return CGSize(width: width, height: topInset)
                }
                return CGSize(width: fallbackSize.width, height: topInset)
            }
        }
        // 无刘海：用菜单栏高度，宽度用默认值
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = max(fallbackSize.height, menuBar > 0 ? menuBar : fallbackSize.height)
        return CGSize(width: fallbackSize.width, height: height)
    }
}

private extension NSScreen {
    /// 是否为内置显示器
    var isBuiltin: Bool {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// 是否有物理刘海（摄像头开窗）
    var hasPhysicalNotch: Bool {
        if #available(macOS 12.0, *) {
            return safeAreaInsets.top > 0
        }
        return false
    }
}
