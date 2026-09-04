import AppKit

/// 鼠标位置监听：全局 + 本地监视器组合。
/// 鼠标事件的全局监视不需要辅助功能/输入监控权限（键盘才需要）。
/// - 全局监视器：收起状态下窗口完全穿透，事件流向其他 App，由它捕获；
/// - 本地监视器：展开状态下鼠标位于面板内，事件先经过本 App，由它捕获。
final class MouseWatch {

    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// 鼠标移动（全局坐标，左下原点）
    var onMove: ((NSPoint) -> Void)?
    /// 鼠标按下（全局坐标）
    var onGlobalClick: ((NSPoint) -> Void)?

    func start() {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .otherMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.onMove?(NSEvent.mouseLocation)
        }

        // 面板自己收到的事件属于"本地"，不会经过全局监视器
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .otherMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.onMove?(NSEvent.mouseLocation)
            return event
        }
    }

    /// 收起状态下还需要监听全局左键点击（用于点击岛屿展开）
    func setClickTracking(_ enabled: Bool) {
        if enabled {
            if globalClickMonitor == nil {
                globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                    self?.onGlobalClick?(NSEvent.mouseLocation)
                }
            }
        } else {
            if let m = globalClickMonitor {
                NSEvent.removeMonitor(m)
                globalClickMonitor = nil
            }
        }
    }

    private var globalClickMonitor: Any?

    func stop() {
        setClickTracking(false)
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    deinit {
        // removeMonitor 必须在 deinit 里手动清理尾随闭包持有的句柄
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
    }
}
