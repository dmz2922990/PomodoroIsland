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
        let hosting = NSHostingView(rootView: rootView)
        // 窗口尺寸由本控制器手动管理；禁用宿主视图自动更新窗口内容尺寸约束，
        // 否则展开动画期间 intrinsic size 变化会与 setFrame 冲突导致崩溃
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        panel.contentView = hosting
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
    /// 是否允许悬停预览（专注进行中 + 物理刘海屏，由外部注入）
    var peekCondition: (() -> Bool)?
    /// 悬停预览态：主岛向下垂降一行显示当前任务
    @Published private(set) var isPeeking = false
    /// 通知内容实测高度（由视图上报）
    private var notificationContentHeight: CGFloat = 300

    /// 通知态 frame：刘海带 + 动态内容高度（与 NotificationIslandView.displayHeight 保持一致）
    private func notificationFrame() -> NSRect {
        let band = NotchScreenInfo.collapsedIslandHeight(on: screen)
        let height = band + notificationContentHeight + 4
        let frame = screen.frame
        return NSRect(x: frame.midX - Self.panelWidth / 2,
                      y: frame.maxY - height,
                      width: Self.panelWidth,
                      height: height)
    }

    private var peekRowHeight: CGFloat { 26 }

    /// 收起与预览共用固定 frame：下方预留一行的空间（透明不可见），
    /// 避免 peek 开合时窗口 resize 与内容动画错位造成整体下移
    private func peekReadyFrame() -> NSRect {
        let base = collapsedIslandRect()
        return NSRect(x: base.minX, y: base.minY - peekRowHeight,
                      width: base.width, height: base.height + peekRowHeight)
    }

    private func openPeek() {
        guard !isPeeking, !isExpanded else { return }
        isPeeking = true
        trace("peek-open")
        applyFrame()
    }

    private func closePeek() {
        guard isPeeking else { return }
        isPeeking = false
        trace("peek-close")
        applyFrame()
    }

    private func shouldAutoPeek() -> Bool {
        peekCondition?() == true
    }

    /// 当前状态对应的窗口 frame
    private func currentFrame() -> NSRect {
        if isExpanded {
            return hasPendingNotifications?() == true ? notificationFrame() : expandedFrame()
        }
        // 收起与预览共用固定高度窗口（预留行透明），杜绝 resize 位移
        return peekReadyFrame()
    }

    private func applyFrame(animated: Bool = false) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                window?.animator().setFrame(currentFrame(), display: true)
            }
        } else {
            window?.setFrame(currentFrame(), display: true)
        }
    }

    /// 通知内容高度变化（视图测量上报）
    func notificationHeightChanged(_ height: CGFloat) {
        let clamped = max(90, height)
        guard abs(clamped - notificationContentHeight) > 1 else { return }
        notificationContentHeight = clamped
        // 只要展开就应用：若额外要求"有待处理通知"，竞态窗口里跳过后探针不会再触发，
        // 窗口会永远卡在旧高度（内容被裁切）。无通知时 currentFrame() 自然回到任务面板帧。
        if isExpanded {
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
        isPeeking = false
        isExpanded = true
        trace("expand")
        window.ignoresMouseEvents = false
        window.staysInteractive = true
        mouseWatch.setClickTracking(false)
        applyFrame(animated: true)
    }

    func collapse() {
        guard isExpanded, let window = window else { return }
        collapseWork?.cancel()
        isPeeking = false
        isExpanded = false
        trace("collapse")
        window.ignoresMouseEvents = true
        window.staysInteractive = false
        mouseWatch.setClickTracking(true)
        applyFrame(animated: true)
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
            // 收起态：专注中悬停主岛 → 垂降一行预览任务；移出或条件解除 → 收回
            dwellWork?.cancel()
            if isPeeking {
                if !shouldAutoPeek() || !NSPointInRect(point, peekReadyFrame().insetBy(dx: -4, dy: -4)) {
                    closePeek()
                }
            } else if shouldAutoPeek(),
                      NSPointInRect(point, collapsedIslandRect().insetBy(dx: -4, dy: -8)) {
                openPeek()
            }
        }
    }

    /// 通知全部结算：一律直接收起刘海条（主动点关闭也一样）
    func settleAfterNotifications() {
        guard isExpanded else { return }
        collapse()
    }

    private func handleGlobalClick(_ point: NSPoint) {
        guard !isExpanded else { return }
        // 主岛带区点击 → 展开
        if NSPointInRect(point, collapsedIslandRect().insetBy(dx: -4, dy: -4)) {
            expand()
            return
        }
        // 预览垂降行点击 → 展开
        if isPeeking, NSPointInRect(point, peekReadyFrame().insetBy(dx: -4, dy: -4)) {
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
