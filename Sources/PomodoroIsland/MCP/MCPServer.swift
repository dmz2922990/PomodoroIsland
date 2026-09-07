import Foundation
import Network

/// 内嵌 MCP 服务（Streamable HTTP + JSON-RPC 2.0，仅监听 127.0.0.1）。
/// 供 AI 客户端（ZCode / Claude 等）对任务增删改查并读取专注状态。
/// 接入方式：MCP 客户端配置 URL  http://127.0.0.1:<port>/mcp
final class MCPServer {

    private let store: TaskStore
    private let engine: PomodoroEngine
    private let notifications: NotificationStore
    let port: UInt16

    private var listener: NWListener?
    /// 并发队列：ask_user 会阻塞线程等待用户响应，串行会卡住其他 MCP 请求
    private let queue = DispatchQueue(label: "pomodoro-island.mcp", attributes: .concurrent)
    /// MCP 会话表：sessionId → 来源默认身份（clientInfo.name），主线程读写
    private var sessions: [String: String] = [:]
    private(set) var isRunning = false
    /// (是否运行中, 说明/错误信息)
    var onStateChange: ((Bool, String) -> Void)?

    private let iso = ISO8601DateFormatter()

    init(store: TaskStore, engine: PomodoroEngine, notifications: NotificationStore, port: UInt16) {
        self.store = store
        self.engine = engine
        self.notifications = notifications
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

    static func parseRequest(_ raw: Data) -> (method: String, path: String, headers: [String: String], body: Data)? {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: raw[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        var contentLength = 0
        for line in lines {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            headers[kv[0].lowercased()] = kv[1]
            if kv[0].lowercased() == "content-length" { contentLength = Int(kv[1]) ?? 0 }
        }
        let bodyData = raw[headerEnd.upperBound...]
        guard bodyData.count >= contentLength else { return nil }
        let path = parts[1].split(separator: "?").first.map(String.init) ?? parts[1]
        return (parts[0], path, headers, Data(bodyData.prefix(contentLength)))
    }

    private func handle(_ req: (method: String, path: String, headers: [String: String], body: Data)) -> Data {
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
        let (body, extraHeaders) = handleRPCMessage(obj, headers: req.headers)
        return httpResponse(status: 200, body: body, extraHeaders: extraHeaders)
    }

    private func httpResponse(status: Int, body: Data, extraHeaders: [String: String] = [:]) -> Data {
        let reason = ["200 OK", "202 Accepted", "400 Bad Request", "404 Not Found", "405 Method Not Allowed"][
            status == 200 ? 0 : status == 202 ? 1 : status == 400 ? 2 : status == 404 ? 3 : 4
        ]
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    // MARK: - JSON-RPC

    private func handleRPCMessage(_ obj: [String: Any], headers: [String: String]) -> (Data, [String: String]) {
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any] ?? [:]

        var response: [String: Any] = ["jsonrpc": "2.0", "id": obj["id"] ?? NSNull()]
        var extraHeaders: [String: String] = [:]
        switch method {
        case "initialize":
            // 会话表：记录来源默认身份并下发会话 id
            let sessionId = UUID().uuidString
            let clientName = (params["clientInfo"] as? [String: Any])?["name"] as? String ?? "未署名 Agent"
            onMain { self.sessions[sessionId] = clientName }
            extraHeaders["MCP-Session-Id"] = sessionId
            response["result"] = [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "pomodoro-island", "version": "1.2.0"],
            ]
        case "ping":
            response["result"] = [String: Any]()
        case "tools/list":
            response["result"] = ["tools": Self.toolDescriptors]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            // 来源解析：调用级 source > 会话默认身份 > 未署名
            let sessionSource: String? = {
                guard let sid = headers["mcp-session-id"] else { return nil }
                return onMain { self.sessions[sid] }
            }()
            let source = (args["source"] as? String) ?? sessionSource ?? "未署名 Agent"
            response["result"] = callTool(name, args, source: source)
        default:
            response["error"] = ["code": -32601, "message": "method not found: \(method)"]
        }
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data("{}".utf8)
        return (data, extraHeaders)
    }

    // MARK: - 工具

    private struct ToolError: Error { let message: String }

    private func callTool(_ name: String, _ args: [String: Any], source: String) -> Any {
        let result: Result<Any, ToolError>
        switch name {
        case "list_tasks": result = toolListTasks(args)
        case "add_task": result = toolAddTask(args)
        case "update_task": result = toolUpdateTask(args)
        case "delete_task": result = toolDeleteTask(args)
        case "set_current_task": result = toolSetCurrent(args)
        case "get_status": result = toolGetStatus()
        case "list_notifications": result = toolListNotifications()
        case "notify": result = toolNotify(args, source: source)
        case "ask_user": result = toolAskUser(args, source: source)
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

    /// 通知队列诊断：待响应 / 历史（状态与来源）
    private func toolListNotifications() -> Result<Any, ToolError> {
        let payload: [String: Any] = onMain { [self] in
            func brief(_ n: IslandNotification) -> [String: Any] {
                var d: [String: Any] = [
                    "id": n.id.uuidString, "source": n.source, "kind": n.kind.rawValue,
                    "title": n.title, "state": n.response?.status ?? "pending",
                ]
                if let r = n.response {
                    if let c = r.clicked { d["clicked"] = c }
                    if !r.selected.isEmpty { d["selected"] = r.selected }
                    if let t = r.text { d["text"] = t }
                }
                return d
            }
            return [
                "pending": notifications.pending.map(brief),
                "history": Array(notifications.history.prefix(10)).map(brief),
            ]
        }
        return .success(payload)
    }

    // MARK: 通知工具

    /// 通知服务开关校验
    private func checkNotifyEnabled() -> ToolError? {
        guard store.settings.notifyEnabled else {
            return ToolError(message: "通知服务已在设置中关闭")
        }
        return nil
    }

    /// 被动通知：发出即返回，自动消失
    private func toolNotify(_ args: [String: Any], source: String) -> Result<Any, ToolError> {
        if let e = checkNotifyEnabled() { return .failure(e) }
        guard let title = args["title"] as? String, !title.isEmpty else {
            return .failure(ToolError(message: "缺少 title"))
        }
        let level = args["level"] as? String ?? "info"
        guard let kind = NotificationKind(rawValue: level), !kind.isInteractive else {
            return .failure(ToolError(message: "level 须为 info / success / warning / error"))
        }
        let message = args["message"] as? String ?? ""
        let autoDismiss = args["autoDismiss"] as? Int ?? 8

        let n = IslandNotification(
            source: source, kind: kind, title: title, message: message,
            autoDismissAfter: TimeInterval(clamp(autoDismiss, 2, 300))
        )
        let payload: Result<Any, ToolError>? = onMain { [self] in
            switch notifications.submit(n) {
            case .success(let submitted):
                return .success(["id": submitted.id.uuidString, "source": source,
                                 "autoDismiss": clamp(autoDismiss, 2, 300)])
            case .failure(let e):
                return .failure(ToolError(message: e.message))
            }
        }
        return payload ?? .failure(ToolError(message: "提交失败"))
    }

    /// 阻塞交互：等用户在岛屿上操作完（或超时）才返回
    private func toolAskUser(_ args: [String: Any], source: String) -> Result<Any, ToolError> {
        if let e = checkNotifyEnabled() { return .failure(e) }
        guard let title = args["title"] as? String, !title.isEmpty else {
            return .failure(ToolError(message: "缺少 title"))
        }
        let type = args["type"] as? String ?? "choice"
        guard let kind = NotificationKind(rawValue: type), kind.isInteractive else {
            return .failure(ToolError(message: "type 须为 buttons / choice / input"))
        }
        let message = args["message"] as? String ?? ""
        let multiSelect = args["multiSelect"] as? Bool ?? false
        let timeout = clamp(args["timeoutSeconds"] as? Int ?? 120, 5, 600)

        var n = IslandNotification(
            source: source, kind: kind, title: title, message: message,
            timeoutSeconds: TimeInterval(timeout)
        )
        switch kind {
        case .buttons:
            let labels = parseStringArray(args["buttons"])
            guard (2...4).contains(labels.count) else {
                return .failure(ToolError(message: "buttons 需要 2-4 个按钮"))
            }
            n.buttons = labels.map { NotificationOption(id: $0, label: $0) }
        case .choice:
            let raw = (args["options"] as? [[String: Any]]) ?? []
            guard (2...6).contains(raw.count) else {
                return .failure(ToolError(message: "options 需要 2-6 个选项 {label, detail?}"))
            }
            n.options = raw.enumerated().map { i, o in
                let label = o["label"] as? String ?? "选项\(i + 1)"
                return NotificationOption(id: "\(i)", label: label, detail: o["detail"] as? String ?? "")
            }
            n.multiSelect = multiSelect
            n.allowCustomInput = args["allowInput"] as? Bool
        case .input:
            n.inputPlaceholder = args["placeholder"] as? String ?? "输入内容…"
        default:
            return .failure(ToolError(message: "type 须为 buttons / choice / input"))
        }

        let box = ResponseBox()
        let registered: Result<Void, ToolError>? = onMain { [self] in
            switch notifications.submit(n) {
            case .success(let submitted):
                notifications.registerCompletion(submitted.id) { resp in
                    box.response = resp
                    box.sem.signal()
                }
                return .success(())
            case .failure(let e):
                return .failure(ToolError(message: e.message))
            }
        }
        switch registered {
        case .failure(let e): return .failure(e)
        default: break
        }

        // 阻塞等待用户操作；超时兜底由 store 的 deadline 定时器结算
        if box.sem.wait(timeout: .now() + .seconds(timeout + 2)) == .timedOut {
            onMain { [self] in notifications.respond(n.id, NotificationResponse(status: "timeout")) }
            _ = box.sem.wait(timeout: .now() + 2)
        }
        let resp = box.response ?? NotificationResponse(status: "timeout")

        var payload: [String: Any] = ["status": resp.status, "source": source]
        if let clicked = resp.clicked { payload["clicked"] = clicked }
        if !resp.selected.isEmpty { payload["selected"] = resp.selected }
        if let text = resp.text { payload["text"] = text }
        return .success(payload)
    }

    private func parseStringArray(_ value: Any?) -> [String] {
        if let arr = value as? [String] { return arr }
        if let arr = value as? [[String: Any]] {
            return arr.enumerated().map { i, d in d["label"] as? String ?? "选项\(i + 1)" }
        }
        return []
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }

    /// ask_user 的响应容器
    private final class ResponseBox {
        let sem = DispatchSemaphore(value: 0)
        var response: NotificationResponse?
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
        [
            "name": "list_notifications",
            "description": "【通知域】查看通知队列状态：待响应列表与最近历史（诊断用）",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "notify",
            "description": "【通知域】向用户发送被动通知（岛屿自动弹出，自动消失），立即返回，不等待用户",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "通知标题"],
                    "message": ["type": "string", "description": "通知正文"],
                    "level": ["type": "string", "enum": ["info", "success", "warning", "error"], "description": "通知级别，默认 info"],
                    "autoDismiss": ["type": "integer", "description": "自动消失秒数，默认 8，范围 2-300"],
                    "source": ["type": "string", "description": "来源身份（Agent 名），用于界面区分，默认取会话身份"],
                ],
                "required": ["title"],
            ],
        ],
        [
            "name": "ask_user",
            "description": "【通知域·阻塞】向用户提问并等待其在岛屿上操作：按钮/单选多选/文本输入。调用会阻塞直到用户响应或超时。注意：任务管理请使用任务域工具，不要用本工具",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "问题标题"],
                    "message": ["type": "string", "description": "补充说明"],
                    "type": ["type": "string", "enum": ["buttons", "choice", "input"], "description": "交互类型"],
                    "buttons": ["type": "array", "items": ["type": "string"], "description": "type=buttons 时的 2-4 个按钮文案"],
                    "options": ["type": "array", "items": ["type": "object", "properties": ["label": ["type": "string"], "detail": ["type": "string"]], "required": ["label"]], "description": "type=choice 时的 2-6 个选项"],
                    "multiSelect": ["type": "boolean", "description": "choice 是否可多选，默认 false"],
                    "allowInput": ["type": "boolean", "description": "choice 是否附带回填输入框（用户可自定义答案），默认 false"],
                    "placeholder": ["type": "string", "description": "type=input 的占位文本"],
                    "timeoutSeconds": ["type": "integer", "description": "等待响应秒数，默认 120，范围 5-600；超时返回 status=timeout"],
                    "source": ["type": "string", "description": "来源身份（Agent 名）"],
                ],
                "required": ["title", "type"],
            ],
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
