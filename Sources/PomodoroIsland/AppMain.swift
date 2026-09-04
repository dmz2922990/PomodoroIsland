import SwiftUI
import Combine
import UserNotifications

@main
struct PomodoroIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = TaskStore()
    private lazy var engine = PomodoroEngine(store: store)
    private lazy var controller = NotchWindowController()

    private var statusItem: NSStatusItem?
    private var cancellables: [AnyCancellable] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        requestNotificationAuthorization()

        let root = NotchRootView()
            .environmentObject(store)
            .environmentObject(engine)
            .environmentObject(controller)

        controller.start(rootView: root)

        installStatusItem()
        observeEngine()

        if ProcessInfo.processInfo.environment["POMO_SELFTEST"] == "1" {
            runSelfTest()
        }
    }

    // MARK: - 自测（POMO_SELFTEST=1）

    private func runSelfTest() {
        func pass(_ name: String, _ ok: Bool, _ detail: String = "") {
            NSLog("SELFTEST \(ok ? "PASS" : "FAIL") \(name) \(detail)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }

            // 1. 直接展开/收起
            self.controller.expand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let w = self.controller.window
                pass("expand-state", self.controller.isExpanded)
                pass("expand-mouse", w?.ignoresMouseEvents == false)
                pass("expand-frame", w?.frame.width ?? 0 > 300, "\(String(describing: w?.frame))")

                // 2. 悬停展开 / 离开收起（直接驱动内部状态机；外部事件注入被 TCC 拦截）
                self.controller.collapse()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let strip = NotchScreenInfo.stripRect(on: NotchScreenInfo.preferredScreen())
                    let center = NSPoint(x: strip.midX, y: strip.midY)
                    self.controller.handleMouseMove(center)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        pass("hover-expand", self.controller.isExpanded)

                        self.controller.handleMouseMove(NSPoint(x: 300, y: 300))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            pass("leave-collapse", !self.controller.isExpanded)

                            // 4. 引擎
                            self.engine.startFocus()
                            let first = self.engine.displayText
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                pass("engine-running", self.engine.running && self.engine.phase == .focus)
                                pass("engine-ticks", self.engine.displayText != first, "\(first) -> \(self.engine.displayText)")

                                // 5. 任务与持久化
                                let before = self.store.tasks.count
                                self.store.addTask(title: "SelfTest 任务")
                                pass("store-add", self.store.tasks.count == before + 1)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                        .appendingPathComponent("PomodoroIsland/store.json")
                                    pass("store-persist", FileManager.default.fileExists(atPath: url.path), url.path)

                                    self.engine.reset()
                                    NSLog("SELFTEST DONE")
                                    NSApp.terminate(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    // MARK: - 菜单栏状态项

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        let menu = NSMenu()
        menu.addItem(withTitle: "展开 / 收起岛屿", action: #selector(toggleIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "开始专注", action: #selector(startFocus), keyEquivalent: "")
        menu.addItem(withTitle: "暂停 / 继续", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 PomodoroIsland", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu

        statusItem = item
        refreshStatusTitle()
    }

    @objc private func toggleIsland() { controller.toggle() }
    @objc private func startFocus() { engine.startFocus() }
    @objc private func togglePause() { engine.togglePause() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }
        let phase = engine.phase
        let symbol: String
        switch phase {
        case .focus: symbol = "🍅"
        case .shortBreak: symbol = "☕"
        case .longBreak: symbol = "🌴"
        case .idle: symbol = "🐚"
        }
        button.title = "\(symbol) \(engine.displayText)"
    }

    /// 引擎每次计时刷新都会触发 objectWillChange，借它刷新菜单栏标题
    private func observeEngine() {
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
    }

    // MARK: - 通知授权

    private func requestNotificationAuthorization() {
        // 裸 swift run（无 bundle）时跳过
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional]) { _, _ in }
    }
}
