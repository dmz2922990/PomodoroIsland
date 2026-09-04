import AppKit

/// 屏幕刘海区域的几何信息。
/// 全部使用 AppKit 公开 API；带物理刘海的屏幕用 safeAreaInsets 精确计算，
/// 没有刘海的屏幕（外接显示器 / 旧机型）则按典型刘海尺寸画一个"虚拟刘海"。
enum NotchScreenInfo {

    /// 典型 MacBook 刘海的近似尺寸（无真实刘海时使用）
    static let fallbackSize = CGSize(width: 200, height: 32)

    /// 收起状态：每侧仅预留一个图标位置
    static let collapsedWing: CGFloat = 28
    /// 展开状态下岛屿头部的延伸高度
    static let expandedExtension: CGFloat = 56

    /// 菜单栏高度（随屏幕与分辨率不同；自动隐藏时回退典型值）
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let h = screen.frame.maxY - screen.visibleFrame.maxY
        return h > 0 ? h : 24
    }

    /// 物理刘海高度（无刘海屏幕返回 0）
    static func physicalNotchHeight(on screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            let top = screen.safeAreaInsets.top
            if top > 0 { return top }
        }
        return 0
    }

    /// 收起岛屿的目标高度：与顶部菜单栏视觉齐平。
    /// 刘海屏 = 刘海高度（物理刘海比菜单栏高，必须盖住）；外接屏 = 菜单栏高度。
    static func collapsedIslandHeight(on screen: NSScreen) -> CGFloat {
        max(physicalNotchHeight(on: screen), menuBarHeight(on: screen))
    }

    /// 收起状态岛屿宽度：刘海宽 + 两侧翅膀
    static func collapsedIslandWidth(on screen: NSScreen) -> CGFloat {
        notchSize(on: screen).width + collapsedWing * 2
    }

    /// 刘海/中央带的宽度
    static func stripWidth(on screen: NSScreen) -> CGFloat {
        notchSize(on: screen).width
    }

    /// 收起状态岛屿矩形：两翼菜单栏高，高度动态对齐菜单栏。屏幕坐标系（左下原点），顶边贴屏幕顶。
    static func collapsedIslandRect(on screen: NSScreen) -> NSRect {
        let strip = stripRect(on: screen)
        let width = strip.width + collapsedWing * 2
        let height = collapsedIslandHeight(on: screen)
        return NSRect(
            x: strip.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
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
                    return CGSize(width: screen.frame.width - left - right, height: topInset)
                }
                return CGSize(width: fallbackSize.width, height: topInset)
            }
        }
        // 无刘海：宽度用默认值，高度与菜单栏一致
        return CGSize(width: fallbackSize.width, height: menuBarHeight(on: screen))
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
