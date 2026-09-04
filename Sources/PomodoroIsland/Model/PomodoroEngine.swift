import Foundation
import AppKit
import UserNotifications

/// 番茄钟阶段
enum Phase: String, Equatable {
    case idle
    case focus
    case shortBreak = "short_break"
    case longBreak = "long_break"

    var label: String {
        switch self {
        case .idle: return "待机"
        case .focus: return "专注中"
        case .shortBreak: return "小憩"
        case .longBreak: return "长休息"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "moon.zzz"
        case .focus: return "brain"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "figure.walk"
        }
    }
}

/// 番茄钟状态机：基于目标时间点（而非累加秒数）计时，系统睡眠也能正确结算。
final class PomodoroEngine: ObservableObject {

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var running = false
    @Published private(set) var endsAt: Date?
    /// 暂停时刻的剩余秒数
    @Published private(set) var pausedRemainder: TimeInterval?
    /// 每 0.5s 更新的"当前时间"，驱动视图重算剩余时间
    @Published private(set) var now = Date()

    /// 阶段切换（含自然结束、跳过）后触发，携带上一阶段是否自然完成
    var onPhaseFinished: ((_ finishedNaturally: Bool, _ from: Phase) -> Void)?

    private let store: TaskStore
    private var ticker: Timer?

    /// 开发调试用：与 NotchWindowController 相同的追踪机制
    private let traceEnabled = ProcessInfo.processInfo.environment["POMO_TRACE"] == "1"

    private func trace(_ message: String) {
        guard traceEnabled else { return }
        TraceLog.append("\(Date().timeIntervalSince1970) engine \(message)")
    }

    init(store: TaskStore) {
        self.store = store
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: - 派生状态

    var phaseDuration: TimeInterval {
        switch phase {
        case .idle: return TimeInterval(store.settings.focusMinutes * 60)
        case .focus: return TimeInterval(store.settings.focusMinutes * 60)
        case .shortBreak: return TimeInterval(store.settings.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(store.settings.longBreakMinutes * 60)
        }
    }

    /// 剩余秒数（向上取整，显示 25:00 起步）
    var remainingSeconds: TimeInterval {
        if running, let endsAt = endsAt {
            return max(0, endsAt.timeIntervalSince(now))
        }
        if let pausedRemainder = pausedRemainder {
            return max(0, pausedRemainder)
        }
        return phaseDuration
    }

    var progress: Double {
        let total = phaseDuration
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remainingSeconds / total))
    }

    var displayText: String {
        let secs = Int(remainingSeconds.rounded(.up))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    // MARK: - 控制

    func startFocus() {
        phase = .focus
        pausedRemainder = nil
        begin(duration: phaseDuration)
    }

    func startBreak() {
        phase = nextBreakPhase()
        pausedRemainder = nil
        begin(duration: phaseDuration)
    }

    func togglePause() {
        if running {
            pausedRemainder = max(0, endsAt?.timeIntervalSinceNow ?? 0)
            running = false
            endsAt = nil
        } else {
            let remain = pausedRemainder ?? phaseDuration
            begin(duration: remain)
        }
    }

    /// 跳过当前阶段（不计入完成）
    func skip() {
        let from = phase
        endPhase(finishedNaturally: false, from: from)
    }

    func reset() {
        phase = .idle
        running = false
        endsAt = nil
        pausedRemainder = nil
    }

    private func begin(duration: TimeInterval) {
        guard duration > 0 else { return }
        endsAt = Date().addingTimeInterval(duration)
        running = true
        trace("phase=\(phase.rawValue) running=true duration=\(Int(duration))")
    }

    private func nextBreakPhase() -> Phase {
        let count = store.todayFocusCount
        return count % max(1, store.settings.longBreakEvery) == 0 ? .longBreak : .shortBreak
    }

    private func idleAfterPhase() {
        phase = .idle
        running = false
        endsAt = nil
        pausedRemainder = nil
    }

    private func tick() {
        now = Date()
        guard running, let endsAt = endsAt else { return }
        if now >= endsAt {
            let from = phase
            endPhase(finishedNaturally: true, from: from)
        }
    }

    private func endPhase(finishedNaturally: Bool, from: Phase) {
        if finishedNaturally, from == .focus {
            store.recordFocusEnd(for: store.currentTaskId)
            notify(title: "🍅 专注完成！", body: breakSuggestionText)
            playSound()
            if store.settings.autoStartBreak {
                startBreak()
            } else {
                idleAfterPhase()
            }
        } else if finishedNaturally, from != .idle {
            notify(title: "☕ 休息结束", body: "回来继续一个番茄吧")
            playSound()
            idleAfterPhase()
        } else {
            idleAfterPhase()
        }
        onPhaseFinished?(finishedNaturally, from)
        objectWillChange.send()
    }

    private var breakSuggestionText: String {
        let s = store.settings
        let isLong = store.todayFocusCount % max(1, s.longBreakEvery) == 0
        let minutes = isLong ? s.longBreakMinutes : s.shortBreakMinutes
        let name = store.currentTask.map { "「\($0.title)」" } ?? ""
        return "已为\(name)记录 1 个番茄。休息 \(minutes) 分钟？"
    }

    // MARK: - 提示

    private func playSound() {
        guard store.settings.soundOn else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    private func notify(title: String, body: String) {
        // 裸 swift run（无 bundle）时通知中心不可用
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "pomodoro-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
