import AppKit
import SwiftUI

/// 追踪日志写入（仅 POMO_TRACE=1 时调用方会走到这里）
enum TraceLog {
    static func append(_ line: String) {
        let url = URL(fileURLWithPath: "/tmp/pomodoro-trace.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

/// 刘海窗口的控制器：负责窗口生命周期、位置跟踪、展开/收起状态机。
final class NotchWindowController: ObservableObject {

    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 492
    /// 判定"离开面板"的外边距
    static let leaveMargin: CGFloat = 14
    /// 离开后多久自动收起
    static let delayToCollapse: TimeInterval = 0.35

    @Published private(set) var isExpanded = false

    /// 开发调试用：POMO_TRACE=1 时把状态变化追加写入 /tmp/pomodoro-trace.log
    private let traceEnabled = ProcessInfo.processInfo.environment["POMO_TRACE"] == "1"

    private func trace(_ message: String) {
        guard traceEnabled else { return }
        TraceLog.append("\(Date().timeIntervalSince1970) \(message)")
    }

    private(set) var window: NotchPanel?
    private let mouseWatch = MouseWatch()
    private var screen: NSScreen
    private var dwellWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    var onToggleBySystem: ((Bool) -> Void)?

    init() {
        screen = NotchScreenInfo.preferredScreen()
    }

    func start(rootView: some View) {
        // 窗口尺寸固定为展开大小，永不变更：展开/收起完全由 SwiftUI 在窗口内驱动。
        // （无边框窗口的 setFrame 动画在收缩时不可靠，曾导致收起后岛屿高度错误）
        // 收起时 ignoresMouseEvents = true， oversized 的窗口不影响点击穿透。
        let panel = NotchPanel(contentRect: expandedFrame())
        // 根视图内已 .ignoresSafeArea()：窗口整体位于屏幕安全区（刘海）内，
        // 若不忽略安全区，SwiftUI 会把岛屿往下推出一个刘海的高度
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        window = panel

        if #available(macOS 12.0, *) {
            NSLog("PomodoroIsland geometry: screen=\(screen.frame) safeArea=\(screen.safeAreaInsets) island=\(collapsedIslandRect()) panelFrame=\(panel.frame)")
        } else {
            NSLog("PomodoroIsland geometry: screen=\(screen.frame) island=\(collapsedIslandRect()) panelFrame=\(panel.frame)")
        }

        mouseWatch.onMove = { [weak self] point in
            DispatchQueue.main.async { self?.handleMouseMove(point) }
        }
        mouseWatch.onGlobalClick = { [weak self] point in
            DispatchQueue.main.async { self?.handleGlobalClick(point) }
        }
        // 自测模式下不启动真实鼠标监听：物理鼠标移动会取消合成测试的悬停任务，
        // 干扰 hover-expand 断言（逻辑本身由 handleMouseMove 直接驱动验证）
        let selfTest = ProcessInfo.processInfo.environment["POMO_SELFTEST"] == "1"
        if !selfTest {
            mouseWatch.start()
            mouseWatch.setClickTracking(true)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionForScreenChange()
        }
    }

    func shutdown() {
        dwellWork?.cancel()
        collapseWork?.cancel()
        mouseWatch.stop()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        window?.close()
        window = nil
    }

    // MARK: - 帧计算

    private var stripRect: NSRect { NotchScreenInfo.stripRect(on: screen) }

    /// 收起状态岛屿的命中区域（仅用于悬停/点击判定，窗口本身尺寸固定）
    private func collapsedIslandRect() -> NSRect {
        NotchScreenInfo.collapsedIslandRect(on: screen)
    }

    private func expandedFrame() -> NSRect {
        let width = Self.panelWidth
        // 一体岛屿：菜单栏/刘海带 + 头部延伸 + 面板，连续无间隙
        let band = NotchScreenInfo.collapsedIslandHeight(on: screen)
        let height = band + NotchScreenInfo.expandedExtension + Self.panelHeight
        let frame = screen.frame
        return NSRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// 展开状态的外部保持条件（如：有待处理通知时不自动收起）
    var shouldStayOpen: (() -> Bool)?
    /// 当前是否有待处理通知（决定展开 frame 用任务面板还是通知岛）
    var hasPendingNotifications: (() -> Bool)?
    /// 通知内容实测高度（由视图上报）
    private var notificationContentHeight: CGFloat = 300

    /// 通知态 frame：刘海带 + 动态内容高度
    private func notificationFrame() -> NSRect {
        let band = NotchScreenInfo.collapsedIslandHeight(on: screen)
        let height = band + notificationContentHeight + 14
        let frame = screen.frame
        return NSRect(x: frame.midX - Self.panelWidth / 2,
                      y: frame.maxY - height,
                      width: Self.panelWidth,
                      height: height)
    }

    /// 当前状态对应的窗口 frame
    private func currentFrame() -> NSRect {
        if isExpanded {
            return hasPendingNotifications?() == true ? notificationFrame() : expandedFrame()
        }
        return collapsedIslandRect()
    }

    private func applyFrame() {
        window?.setFrame(currentFrame(), display: true)
    }

    /// 通知内容高度变化（视图测量上报）
    func notificationHeightChanged(_ height: CGFloat) {
        let clamped = max(120, height)
        guard abs(clamped - notificationContentHeight) > 1 else { return }
        notificationContentHeight = clamped
        if isExpanded, hasPendingNotifications?() == true {
            applyFrame()
        }
    }

    private var interactiveFrame: NSRect {
        (window?.frame ?? collapsedIslandRect())
            .insetBy(dx: -Self.leaveMargin, dy: -Self.leaveMargin)
    }

    // MARK: - 展开 / 收起

    func expand() {
        guard !isExpanded, let window = window else { return }
        dwellWork?.cancel()
        collapseWork?.cancel()
        isExpanded = true
        trace("expand")
        window.ignoresMouseEvents = false
        window.staysInteractive = true
        mouseWatch.setClickTracking(false)
        applyFrame()
    }

    func collapse() {
        guard isExpanded, let window = window else { return }
        collapseWork?.cancel()
        isExpanded = false
        trace("collapse")
        window.ignoresMouseEvents = true
        window.staysInteractive = false
        mouseWatch.setClickTracking(true)
        applyFrame()
    }

    func toggle() {
        isExpanded ? collapse() : expand()
    }

    func handleMouseMove(_ point: NSPoint) {
        if isExpanded {
            if NSPointInRect(point, interactiveFrame) {
                if collapseWork != nil {
                    trace("move:inside-cancel-collapse")
                }
                collapseWork?.cancel()
            } else if shouldStayOpen?() != true {
                trace("move:outside-schedule-collapse")
                scheduleCollapse()
            } else {
                // 保持展开（有待处理通知），仅取消已排期的收起
                collapseWork?.cancel()
            }
        } else {
            // 点击展开：悬停不再触发展开，只清理可能残留的展开任务
            dwellWork?.cancel()
        }
    }

    /// 通知全部结算：光标在面板上则切回任务面板（自然悬停），否则直接收起，
    /// 不经过"任务面板闪现"的中间态
    func settleAfterNotifications() {
        guard isExpanded else { return }
        if NSPointInRect(NSEvent.mouseLocation, interactiveFrame) {
            applyFrame()
        } else {
            collapse()
        }
    }

    private func handleGlobalClick(_ point: NSPoint) {
        if !isExpanded, NSPointInRect(point, collapsedIslandRect().insetBy(dx: -4, dy: -4)) {
            expand()
        }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delayToCollapse, execute: work)
    }

    // MARK: - 屏幕变化

    private func repositionForScreenChange() {
        screen = NotchScreenInfo.preferredScreen()
        window?.setFrame(expandedFrame(), display: true)
    }
}

private extension NSWindow {
    /// 平滑地改变窗口帧（不激活 App）
    func setFrameWithAnimation(_ frame: NSRect) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.2
        NSAnimationContext.current.allowsImplicitAnimation = true
        setFrame(frame, display: true, animate: true)
        NSAnimationContext.endGrouping()
    }
}
