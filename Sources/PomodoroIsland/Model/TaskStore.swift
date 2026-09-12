import Foundation

/// 一个待办任务
struct TaskItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    /// 已完成的番茄数
    var pomosDone: Int = 0
    /// 计划番茄数（可选）
    var pomosPlanned: Int?
    var createdAt: Date = Date()
    var finishedAt: Date?
}

/// 应用设置
struct AppSettings: Codable, Equatable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    /// 每完成多少个番茄进入长休息
    var longBreakEvery: Int = 4
    /// 番茄结束是否自动开始休息
    var autoStartBreak: Bool = false
    /// 提示音开关
    var soundOn: Bool = true
    /// MCP 服务开关（供 AI 客户端增删改查任务）
    var mcpEnabled: Bool = true
    /// MCP 监听端口
    var mcpPort: Int = 9527
    /// 通知服务开关（供 AI 发通知/提问，岛屿展示并可交互）
    var notifyEnabled: Bool = true
    /// 通知到达时自动弹出岛屿
    var notifyAutoExpand: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
        case autoStartBreak, soundOn, mcpEnabled, mcpPort
        case notifyEnabled, notifyAutoExpand
    }

    // 兼容旧格式：新增字段缺失时用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        longBreakEvery = try c.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? 4
        autoStartBreak = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? false
        soundOn = try c.decodeIfPresent(Bool.self, forKey: .soundOn) ?? true
        mcpEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? true
        mcpPort = try c.decodeIfPresent(Int.self, forKey: .mcpPort) ?? 9527
        notifyEnabled = try c.decodeIfPresent(Bool.self, forKey: .notifyEnabled) ?? true
        notifyAutoExpand = try c.decodeIfPresent(Bool.self, forKey: .notifyAutoExpand) ?? true
    }
}

/// 一次完成番茄的记录
struct FocusEntry: Codable, Equatable {
    var date: Date
    /// 是否按时完成（超时腐烂的不计入轮次）
    var onTime: Bool
    /// 完成时关联的任务（旧格式数据为 nil）
    var taskId: UUID?
}

/// 任务与设置的全局存储（JSON 持久化到 Application Support）
final class TaskStore: ObservableObject {

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var settings = AppSettings()
    @Published var currentTaskId: UUID?
    /// 每个完成番茄的记录，用于统计"今日"与轮次
    @Published private(set) var focusLog: [FocusEntry] = []
    /// MCP 服务运行状态（设置页展示）
    @Published var mcpStatusText: String = ""

    /// 完成当前任务时的回调（自动停止专注）；由 AppDelegate 注入
    var onCurrentTaskCompleted: (() -> Void)?
    /// 设置变更回调（用于重启 MCP 服务等）
    var onSettingsChanged: (() -> Void)?

    var todayFocusCount: Int {
        let cal = Calendar.current
        return focusLog.filter { cal.isDateInToday($0.date) }.count
    }

    /// 今天按时完成的番茄数（轮次颜色依据）
    var todayOnTimeCount: Int {
        let cal = Calendar.current
        return focusLog.filter { cal.isDateInToday($0.date) && $0.onTime }.count
    }

    // MARK: - 统计（供统计页与导出）

    struct DailyStat: Identifiable, Equatable {
        let id: Date
        let date: Date
        let count: Int
        let onTimeCount: Int
    }

    /// 近 N 天逐日番茄统计（含今天，缺数日补零）
    func dailyStats(days: Int) -> [DailyStat] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        var result: [DailyStat] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let entries = focusLog.filter { $0.date >= day && $0.date < next }
            result.append(DailyStat(
                id: day, date: day,
                count: entries.count,
                onTimeCount: entries.filter { $0.onTime }.count
            ))
        }
        return result
    }

    /// 近 N 天按时完成率（0-1，无记录返回 nil）
    func onTimeRate(days: Int) -> Double? {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date()))!
        let entries = focusLog.filter { $0.date >= start }
        guard !entries.isEmpty else { return nil }
        return Double(entries.filter { $0.onTime }.count) / Double(entries.count)
    }

    struct TaskRank: Identifiable {
        let id: UUID
        let title: String
        let pomosDone: Int
        let planned: Int?
        let isDone: Bool
    }

    /// 任务番茄排行（按已完成数降序）
    func taskRanking(limit: Int = 5) -> [TaskRank] {
        tasks
            .filter { $0.pomosDone > 0 }
            .sorted { $0.pomosDone > $1.pomosDone }
            .prefix(limit)
            .map { TaskRank(id: $0.id, title: $0.title, pomosDone: $0.pomosDone, planned: $0.pomosPlanned, isDone: $0.isDone) }
    }

    var currentTask: TaskItem? {
        tasks.first { $0.id == currentTaskId && !$0.isDone }
    }

    private var saveWork: DispatchWorkItem?
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PomodoroIsland", isDirectory: true)
        fileURL = dir.appendingPathComponent("store.json")
        load()
    }

    // MARK: - 任务操作

    /// 新任务插入到未完成列表的末尾（最上方优先级最高）
    @discardableResult
    func addTask(title: String, planned: Int? = nil) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var item = TaskItem(title: trimmed)
        item.pomosPlanned = planned
        let insertIndex = tasks.firstIndex(where: { $0.isDone }) ?? tasks.count
        tasks.insert(item, at: insertIndex)
        if currentTaskId == nil {
            currentTaskId = item.id
        }
        scheduleSave()
        return item
    }

    /// 完成当前任务后自动切到最上方（最高优先级）的未完成任务
    func toggleDone(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        setDone(id, !tasks[idx].isDone)
    }

    func setDone(_ id: UUID, _ done: Bool) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }), tasks[idx].isDone != done else { return }
        let wasCurrent = tasks[idx].id == currentTaskId
        tasks[idx].isDone = done
        tasks[idx].finishedAt = done ? Date() : nil
        if done, wasCurrent {
            currentTaskId = tasks.first(where: { !$0.isDone })?.id
            onCurrentTaskCompleted?()
        }
        scheduleSave()
    }

    func deleteTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        if currentTaskId == id {
            currentTaskId = tasks.first(where: { !$0.isDone })?.id
        }
        scheduleSave()
    }

    func setCurrent(_ id: UUID) {
        guard tasks.contains(where: { $0.id == id && !$0.isDone }) else { return }
        currentTaskId = id
        scheduleSave()
    }

    /// 拖拽排序：在对应分页（未完成/已完成）内移动任务
    func moveTask(inDoneList done: Bool, fromId: UUID, toId: UUID) {
        let indices = tasks.indices.filter { tasks[$0].isDone == done }
        var list = indices.map { tasks[$0] }
        guard let from = list.firstIndex(where: { $0.id == fromId }),
              let to = list.firstIndex(where: { $0.id == toId }),
              from != to else { return }
        let item = list.remove(at: from)
        list.insert(item, at: to)
        for (i, idx) in indices.enumerated() {
            tasks[idx] = list[i]
        }
        scheduleSave()
    }

    func setPlanned(_ count: Int, for id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].pomosPlanned = max(0, count)
        scheduleSave()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].title = trimmed
        scheduleSave()
    }

    /// 番茄完成时由引擎调用（onTime=false 表示超时后腐烂收场）
    func recordFocusEnd(for taskId: UUID?, onTime: Bool = true) {
        if let taskId = taskId, let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].pomosDone += 1
        }
        focusLog.append(FocusEntry(date: Date(), onTime: onTime, taskId: taskId))
        // 防止无限增长
        let cal = Calendar.current
        focusLog.removeAll { cal.date(byAdding: .day, value: -60, to: Date())! > $0.date }
        scheduleSave()
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        scheduleSave()
        onSettingsChanged?()
    }

    // MARK: - 持久化（防抖）

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private struct Snapshot: Codable {
        var tasks: [TaskItem]
        var settings: AppSettings
        var currentTaskId: UUID?
        var focusLog: [FocusEntry]

        init(tasks: [TaskItem], settings: AppSettings, currentTaskId: UUID?, focusLog: [FocusEntry]) {
            self.tasks = tasks
            self.settings = settings
            self.currentTaskId = currentTaskId
            self.focusLog = focusLog
        }

        // 兼容旧版 focusLog: [Date] 格式（旧记录一律视为按时完成）
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tasks = try c.decode([TaskItem].self, forKey: .tasks)
            settings = try c.decode(AppSettings.self, forKey: .settings)
            currentTaskId = try c.decodeIfPresent(UUID.self, forKey: .currentTaskId)
            if let entries = try? c.decode([FocusEntry].self, forKey: .focusLog) {
                focusLog = entries
            } else {
                let dates = (try? c.decode([Date].self, forKey: .focusLog)) ?? []
                focusLog = dates.map { FocusEntry(date: $0, onTime: true) }
            }
        }
    }

    private func saveNow() {
        let snapshot = Snapshot(
            tasks: tasks,
            settings: settings,
            currentTaskId: currentTaskId,
            focusLog: focusLog
        )
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("PomodoroIsland save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            // 保留用户手动排序的顺序（数组顺序即优先级，最上方最高）
            tasks = snapshot.tasks
            settings = snapshot.settings
            currentTaskId = snapshot.currentTaskId
            focusLog = snapshot.focusLog
            if currentTaskId != nil, currentTask == nil {
                currentTaskId = tasks.first(where: { !$0.isDone })?.id
            }
        } catch {
            NSLog("PomodoroIsland load failed: \(error)")
        }
    }
}
