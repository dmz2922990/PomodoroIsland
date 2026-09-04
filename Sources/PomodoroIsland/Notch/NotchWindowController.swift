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
    static let panelHeight: CGFloat = 500
    /// 判定"离开面板"的外边距
    static let leaveMargin: CGFloat = 14
    /// 悬停停留多久才展开（毫秒）
    static let dwellToExpand: TimeInterval = 0.12
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
        let panel = NotchPanel(contentRect: collapsedFrame())
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        window = panel

        if #available(macOS 12.0, *) {
            NSLog("PomodoroIsland geometry: screen=\(screen.frame) safeArea=\(screen.safeAreaInsets) strip=\(collapsedFrame()) panelFrame=\(panel.frame)")
        } else {
            NSLog("PomodoroIsland geometry: screen=\(screen.frame) strip=\(collapsedFrame()) panelFrame=\(panel.frame)")
        }

        mouseWatch.onMove = { [weak self] point in
            DispatchQueue.main.async { self?.handleMouseMove(point) }
        }
        mouseWatch.onGlobalClick = { [weak self] point in
            DispatchQueue.main.async { self?.handleGlobalClick(point) }
        }
        mouseWatch.start()
        mouseWatch.setClickTracking(true)

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

    private func collapsedFrame() -> NSRect { stripRect }

    private func expandedFrame() -> NSRect {
        let strip = stripRect
        let width = Self.panelWidth
        // 岛屿高度 + 与面板的间隙 + 面板高度（含底部留白）
        let height = strip.height + 6 + Self.panelHeight
        let frame = screen.frame
        return NSRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    private var interactiveFrame: NSRect {
        (window?.frame ?? collapsedFrame())
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
        mouseWatch.setClickTracking(false)
        window.setFrameWithAnimation(expandedFrame())
    }

    func collapse() {
        guard isExpanded, let window = window else { return }
        collapseWork?.cancel()
        isExpanded = false
        trace("collapse")
        window.ignoresMouseEvents = true
        mouseWatch.setClickTracking(true)
        window.setFrameWithAnimation(collapsedFrame())
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
            } else {
                trace("move:outside-schedule-collapse")
                scheduleCollapse()
            }
        } else {
            // 悬停在刘海条内稍作停留后展开
            if NSPointInRect(point, stripRect.insetBy(dx: -4, dy: -4)) {
                dwellWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.expand()
                }
                dwellWork = work
                trace("move:in-strip-schedule-dwell")
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwellToExpand, execute: work)
            } else {
                dwellWork?.cancel()
            }
        }
    }

    private func handleGlobalClick(_ point: NSPoint) {
        if !isExpanded, NSPointInRect(point, stripRect.insetBy(dx: -4, dy: -4)) {
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
        window?.setFrameWithAnimation(isExpanded ? expandedFrame() : collapsedFrame())
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
