import Foundation
import SwiftUI

/// 通知类型：info/success/warning/error 为被动展示；buttons/choice/input 为阻塞交互
enum NotificationKind: String, CaseIterable {
    case info, success, warning, error
    case buttons, choice, input

    var isInteractive: Bool { self == .buttons || self == .choice || self == .input }

    var color: Color {
        switch self {
        case .info: return Color(red: 0.19, green: 0.72, blue: 0.78)
        case .success: return Color(red: 0.35, green: 0.78, blue: 0.44)
        case .warning: return Color(red: 1.0, green: 0.84, blue: 0.25)
        case .error: return Color(red: 0.95, green: 0.30, blue: 0.25)
        case .buttons, .choice, .input: return Color(red: 1.0, green: 0.42, blue: 0.34)
        }
    }

    var label: String {
        switch self {
        case .info: return "通知"
        case .success: return "成功"
        case .warning: return "警告"
        case .error: return "错误"
        case .buttons: return "待操作"
        case .choice: return "待选择"
        case .input: return "待输入"
        }
    }
}

/// 交互选项 / 按钮
struct NotificationOption: Identifiable, Equatable {
    let id: String
    let label: String
    var detail: String = ""
}

/// 用户对一条通知的响应
struct NotificationResponse: Equatable {
    /// answered / dismissed / timeout
    var status: String
    var clicked: String?
    var selected: [String] = []
    var text: String?
}

/// 一条通知
struct IslandNotification: Identifiable, Equatable {
    let id: UUID = UUID()
    var source: String
    var kind: NotificationKind
    var title: String
    var message: String
    var buttons: [NotificationOption] = []
    var options: [NotificationOption] = []
    var multiSelect: Bool = false
    var inputPlaceholder: String = ""
    /// 被动通知自动消失秒数
    var autoDismissAfter: TimeInterval?
    /// 交互通知响应截止秒数
    var timeoutSeconds: TimeInterval?
    var creation = Date()
    var response: NotificationResponse?
    var respondedAt: Date?

    var isInteractive: Bool { kind.isInteractive }
    var deadline: Date? { timeoutSeconds.map { creation.addingTimeInterval($0) } }
    var expiry: Date? { autoDismissAfter.map { creation.addingTimeInterval($0) } }
}

/// 通知提交失败的错误
struct NotificationSubmitError: Error { let message: String }

/// 通知队列与响应中枢（主线程对象）
/// MCPServer 提交通知并注册完成回调；岛屿 UI 调用 respond 结算并触发回调。
final class NotificationStore: ObservableObject {

    @Published var pending: [IslandNotification] = []   // index 0 = 最新
    @Published private(set) var history: [IslandNotification] = []

    static let maxInteractiveTotal = 3
    static let maxInteractivePerSource = 2
    static let maxPassiveTotal = 5
    static let maxHistory = 20

    /// 到达提示音（由设置同步）
    var soundOn = true
    /// 通知到达时自动展开岛屿
    var onArrival: (() -> Void)?

    private var completions: [UUID: (NotificationResponse) -> Void] = [:]
    private var timer: Timer?

    /// 当前展示中的通知（最新一条）
    var current: IslandNotification? { pending.first }
    var interactivePendingCount: Int { pending.filter { $0.isInteractive }.count }

    // MARK: - 提交（MCPServer 调用，主线程）

    @discardableResult
    func submit(_ n: IslandNotification) -> Result<IslandNotification, NotificationSubmitError> {
        if n.isInteractive {
            let interactive = pending.filter { $0.isInteractive }
            guard interactive.count < Self.maxInteractiveTotal else {
                return .failure(NotificationSubmitError(message: "已有 \(interactive.count) 条待响应通知（上限 \(Self.maxInteractiveTotal)），请稍后再试"))
            }
            let fromSource = interactive.filter { $0.source == n.source }
            guard fromSource.count < Self.maxInteractivePerSource else {
                return .failure(NotificationSubmitError(message: "来源「\(n.source)」已有 \(fromSource.count) 条待响应通知，请先等待处理"))
            }
        } else {
            let passive = pending.filter { !$0.isInteractive }
            if passive.count >= Self.maxPassiveTotal, let oldest = passive.last {
                finish(oldest.id, NotificationResponse(status: "dismissed"))
            }
        }

        pending.insert(n, at: 0)
        startTimerIfNeeded()
        if soundOn { NSSound(named: NSSound.Name("Pong"))?.play() }
        onArrival?()
        return .success(n)
    }

    /// 注册响应回调（MCPServer 阻塞等待用）
    func registerCompletion(_ id: UUID, _ completion: @escaping (NotificationResponse) -> Void) {
        completions[id] = completion
    }

    // MARK: - 结算（UI 点击 / 超时兜底）

    func respond(_ id: UUID, _ response: NotificationResponse) {
        finish(id, response)
    }

    /// 每秒由定时器驱动：交互超时、被动过期
    func checkDeadlines() {
        let now = Date()
        for n in pending where n.response == nil {
            if let dl = n.deadline, now >= dl {
                finish(n.id, NotificationResponse(status: "timeout"))
            } else if let exp = n.expiry, now >= exp {
                finish(n.id, NotificationResponse(status: "dismissed"))
            }
        }
    }

    private func finish(_ id: UUID, _ response: NotificationResponse) {
        guard let idx = pending.firstIndex(where: { $0.id == id }) else { return }
        let n = pending.remove(at: idx)
        guard n.response == nil else { return }
        var settled = n
        settled.response = response
        settled.respondedAt = Date()
        history.insert(settled, at: 0)
        if history.count > Self.maxHistory { history.removeLast() }
        objectWillChange.send()
        completions.removeValue(forKey: id)?(response)
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkDeadlines() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
