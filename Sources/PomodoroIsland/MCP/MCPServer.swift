import Foundation
import Network

/// 内嵌 MCP 服务（Streamable HTTP + JSON-RPC 2.0，仅监听 127.0.0.1）。
/// 供 AI 客户端（ZCode / Claude 等）对任务增删改查并读取专注状态。
/// 接入方式：MCP 客户端配置 URL  http://127.0.0.1:<port>/mcp
final class MCPServer {

    private let store: TaskStore
    private let engine: PomodoroEngine
    let port: UInt16

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pomodoro-island.mcp")
    private(set) var isRunning = false
    /// (是否运行中, 说明/错误信息)
    var onStateChange: ((Bool, String) -> Void)?

    private let iso = ISO8601DateFormatter()

    init(store: TaskStore, engine: PomodoroEngine, port: UInt16) {
        self.store = store
        self.engine = engine
        self.port = port
    }

    // MARK: - 生命周期

    func start() {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            onStateChange?(false, "端口 \(port) 无效")
            return
        }
        let l: NWListener
        do {
            l = try NWListener(using: NWParameters.tcp, on: nwPort)
        } catch {
            isRunning = false
            onStateChange?(false, "启动失败：端口 \(port) 不可用（\(error.localizedDescription)）")
            return
        }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                self?.onStateChange?(true, "运行中")
            case .failed(let error):
                self?.isRunning = false
                self?.listener = nil
                self?.onStateChange?(false, "启动失败：\(error.localizedDescription)")
            default:
                break
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener = l
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - HTTP（最小实现，逐连接处理，响应后关闭）

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        read(conn, Data())
    }

    private func read(_ conn: NWConnection, _ buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, _ in
            guard let self, conn.state == .ready else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let request = Self.parseRequest(buf) {
                self.send(conn, self.handle(request))
            } else if isComplete || buf.count > (1 << 20) {
                conn.cancel()
            } else {
                self.read(conn, buf)
            }
        }
    }

    private func send(_ conn: NWConnection, _ response: Data) {
        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    static func parseRequest(_ raw: Data) -> (method: String, path: String, body: Data)? {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: raw[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }
        var contentLength = 0
        for line in lines where line.lowercased().hasPrefix("content-length:") {
            contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyData = raw[headerEnd.upperBound...]
        guard bodyData.count >= contentLength else { return nil }
        let path = parts[1].split(separator: "?").first.map(String.init) ?? parts[1]
        return (parts[0], path, Data(bodyData.prefix(contentLength)))
    }

    private func handle(_ req: (method: String, path: String, body: Data)) -> Data {
        guard req.path == "/mcp" else {
            return httpResponse(status: 404, body: rpcError(id: NSNull(), code: -32601, message: "not found"))
        }
        guard req.method == "POST" else {
            return httpResponse(status: 405, body: rpcError(id: NSNull(), code: -32601, message: "use POST /mcp"))
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else {
            return httpResponse(status: 400, body: rpcError(id: NSNull(), code: -32700, message: "parse error"))
        }
        // 通知（无 id）不回应答
        guard obj["id"] != nil else {
            return httpResponse(status: 202, body: Data())
        }
        return httpResponse(status: 200, body: handleRPCMessage(obj))
    }

    private func httpResponse(status: Int, body: Data) -> Data {
        let reason = ["200 OK", "202 Accepted", "400 Bad Request", "404 Not Found", "405 Method Not Allowed"][
            status == 200 ? 0 : status == 202 ? 1 : status == 400 ? 2 : status == 404 ? 3 : 4
        ]
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    // MARK: - JSON-RPC

    private func handleRPCMessage(_ obj: [String: Any]) -> Data {
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any] ?? [:]

        var response: [String: Any] = ["jsonrpc": "2.0", "id": obj["id"] ?? NSNull()]
        switch method {
        case "initialize":
            response["result"] = [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "pomodoro-island", "version": "1.1.0"],
            ]
        case "ping":
            response["result"] = [String: Any]()
        case "tools/list":
            response["result"] = ["tools": Self.toolDescriptors]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            response["result"] = callTool(name, args)
        default:
            response["error"] = ["code": -32601, "message": "method not found: \(method)"]
        }
        return (try? JSONSerialization.data(withJSONObject: response)) ?? Data("{}".utf8)
    }

    // MARK: - 工具

    private struct ToolError: Error { let message: String }

    private func callTool(_ name: String, _ args: [String: Any]) -> Any {
        let result: Result<Any, ToolError>
        switch name {
        case "list_tasks": result = toolListTasks(args)
        case "add_task": result = toolAddTask(args)
        case "update_task": result = toolUpdateTask(args)
        case "delete_task": result = toolDeleteTask(args)
        case "set_current_task": result = toolSetCurrent(args)
        case "get_status": result = toolGetStatus()
        default: result = .failure(ToolError(message: "未知工具: \(name)"))
        }
        switch result {
        case .success(let payload):
            return ["content": [["type": "text", "text": prettyJSON(payload)]], "isError": false]
        case .failure(let e):
            return ["content": [["type": "text", "text": e.message]], "isError": true]
        }
    }

    private func toolListTasks(_ args: [String: Any]) -> Result<Any, ToolError> {
        let filter = args["filter"] as? String ?? "all"
        let payload: [String: Any] = onMain { [self] in
            let items = store.tasks.filter { t in
                switch filter {
                case "open": return !t.isDone
                case "done": return t.isDone
                default: return true
                }
            }.map { taskDict($0) }
            return ["count": items.count, "tasks": items]
        }
        return .success(payload)
    }

    private func toolAddTask(_ args: [String: Any]) -> Result<Any, ToolError> {
        guard let title = args["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure(ToolError(message: "缺少 title"))
        }
        let planned = args["planned"] as? Int
        let payload: [String: Any]? = onMain { [self] in
            guard let item = store.addTask(title: title, planned: planned) else { return nil }
            return taskDict(item)
        }
        guard let payload else { return .failure(ToolError(message: "添加失败")) }
        return .success(payload)
    }

    private func toolUpdateTask(_ args: [String: Any]) -> Result<Any, ToolError> {
        guard let id = parseId(args) else { return .failure(ToolError(message: "缺少有效的 id")) }
        let title = args["title"] as? String
        let isDone = args["isDone"] as? Bool
        let planned = args["planned"] as? Int
        guard title != nil || isDone != nil || planned != nil else {
            return .failure(ToolError(message: "没有要更新的字段（title / isDone / planned）"))
        }
        let payload: Result<Any, ToolError>? = onMain { [self] in
            guard store.tasks.contains(where: { $0.id == id }) else { return nil }
            if let title { store.rename(id, to: title) }
            if let isDone { store.setDone(id, isDone) }
            if let planned { store.setPlanned(planned, for: id) }
            guard let t = store.tasks.first(where: { $0.id == id }) else { return nil }
            return .success(taskDict(t))
        }
        switch payload {
        case .success(let d): return .success(d)
        case .failure(let e): return .failure(e)
        case nil: return .failure(ToolError(message: "任务不存在: \(id.uuidString)"))
        }
    }

    private func toolDeleteTask(_ args: [String: Any]) -> Result<Any, ToolError> {
        guard let id = parseId(args) else { return .failure(ToolError(message: "缺少有效的 id")) }
        let existed = onMain { [self] () -> Bool in
            guard store.tasks.contains(where: { $0.id == id }) else { return false }
            store.deleteTask(id)
            return true
        }
        return existed
            ? .success(["deleted": true, "id": id.uuidString])
            : .failure(ToolError(message: "任务不存在: \(id.uuidString)"))
    }

    private func toolSetCurrent(_ args: [String: Any]) -> Result<Any, ToolError> {
        guard let id = parseId(args) else { return .failure(ToolError(message: "缺少有效的 id")) }
        let ok = onMain { [self] () -> Bool in
            store.setCurrent(id)
            return store.currentTaskId == id
        }
        return ok
            ? .success(["currentTaskId": id.uuidString])
            : .failure(ToolError(message: "设置失败（任务不存在或已完成）"))
    }

    private func toolGetStatus() -> Result<Any, ToolError> {
        let payload: [String: Any] = onMain { [self] in
            var d: [String: Any] = [
                "phase": engine.phase.rawValue,
                "running": engine.running,
                "overtime": engine.isOvertime,
                "displayTime": engine.displayText,
                "remainingSeconds": Int(engine.remainingSeconds),
                "todayFocusCount": store.todayFocusCount,
            ]
            d["currentTask"] = store.currentTask?.title ?? NSNull()
            return d
        }
        return .success(payload)
    }

    // MARK: - 工具描述（JSON Schema）

    private static let taskObjectSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "id": ["type": "string"],
            "title": ["type": "string"],
            "isDone": ["type": "boolean"],
            "pomosDone": ["type": "integer"],
            "pomosPlanned": ["type": "integer"],
            "isCurrent": ["type": "boolean"],
            "createdAt": ["type": "string"],
        ],
    ]

    private static let toolDescriptors: [[String: Any]] = [
        [
            "name": "list_tasks",
            "description": "列出番茄钟任务，可按状态过滤",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "filter": ["type": "string", "enum": ["open", "done", "all"], "description": "过滤，默认 all"],
                ],
            ],
        ],
        [
            "name": "add_task",
            "description": "新增任务（加入未完成列表末尾）",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "任务标题"],
                    "planned": ["type": "integer", "description": "计划番茄数（可选）"],
                ],
                "required": ["title"],
            ],
        ],
        [
            "name": "update_task",
            "description": "更新任务：改名 / 标记完成或恢复 / 设计划番茄数。完成当前任务会自动停止进行中的专注",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "任务 id（来自 list_tasks）"],
                    "title": ["type": "string"],
                    "isDone": ["type": "boolean"],
                    "planned": ["type": "integer"],
                ],
                "required": ["id"],
            ],
        ],
        [
            "name": "delete_task",
            "description": "删除任务",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"],
            ],
        ],
        [
            "name": "set_current_task",
            "description": "把某个未完成任务设为当前任务（之后的番茄计入它）",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"],
            ],
        ],
        [
            "name": "get_status",
            "description": "读取专注计时状态：阶段、剩余时间、今日番茄数、当前任务",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
    ]

    // MARK: - 辅助

    private func parseId(_ args: [String: Any]) -> UUID? {
        guard let s = args["id"] as? String else { return nil }
        return UUID(uuidString: s)
    }

    /// 任务 → MCP 返回字典（需在主线程调用）
    private func taskDict(_ t: TaskItem) -> [String: Any] {
        var d: [String: Any] = [
            "id": t.id.uuidString,
            "title": t.title,
            "isDone": t.isDone,
            "pomosDone": t.pomosDone,
            "isCurrent": t.id == store.currentTaskId,
            "createdAt": iso.string(from: t.createdAt),
        ]
        if let p = t.pomosPlanned { d["pomosPlanned"] = p }
        if let f = t.finishedAt { d["finishedAt"] = iso.string(from: f) }
        return d
    }

    /// 主线程同步执行（TaskStore/Engine 是主线程对象）
    @discardableResult
    private func onMain<T>(_ work: @escaping () -> T) -> T {
        if Thread.isMainThread { return work() }
        var result: T!
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            result = work()
            sem.signal()
        }
        sem.wait()
        return result
    }

    private func prettyJSON(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private func rpcError(id: Any, code: Int, message: String) -> Data {
        let obj: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
    }
}
