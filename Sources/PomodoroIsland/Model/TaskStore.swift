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

    /// 归档时未完成任务置顶排序用
    var sortKey: Date { isDone ? (finishedAt ?? .distantPast) : createdAt }
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
}

/// 任务与设置的全局存储（JSON 持久化到 Application Support）
final class TaskStore: ObservableObject {

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var settings = AppSettings()
    @Published var currentTaskId: UUID?
    /// 每个完成番茄的结束时间，用于统计"今日"
    @Published private(set) var focusLog: [Date] = []

    var todayFocusCount: Int {
        let cal = Calendar.current
        return focusLog.filter { cal.isDateInToday($0) }.count
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

    func addTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = TaskItem(title: trimmed)
        tasks.insert(item, at: 0)
        if currentTaskId == nil {
            currentTaskId = item.id
        }
        scheduleSave()
    }

    func toggleDone(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isDone.toggle()
        tasks[idx].finishedAt = tasks[idx].isDone ? Date() : nil
        if tasks[idx].isDone, tasks[idx].id == currentTaskId {
            currentTaskId = tasks.first(where: { !$0.isDone })?.id
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

    /// 番茄完成时由引擎调用
    func recordFocusEnd(for taskId: UUID?) {
        if let taskId = taskId, let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].pomosDone += 1
        }
        focusLog.append(Date())
        // 防止无限增长
        let cal = Calendar.current
        focusLog.removeAll { cal.date(byAdding: .day, value: -60, to: Date())! > $0 }
        scheduleSave()
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        scheduleSave()
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
        var focusLog: [Date]
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
            tasks = snapshot.tasks.sorted { $0.sortKey > $1.sortKey }
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
