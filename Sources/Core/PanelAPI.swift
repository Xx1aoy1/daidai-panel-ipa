import Foundation

// 面板接口封装：这里只做「路径 + 参数 + 类型」的映射，UI 不直接拼 URL。
// 所有路径都以 `/api/v1` 为前缀，兼容面板同时挂载的 `/api` 旧前缀（本客户端统一走 v1）。
extension APIClient {

    // MARK: - 认证

    func checkInit() async throws -> Bool {
        let data = try await send(path: "/auth/check-init", authorized: false, canRefresh: false)
        let status: InitStatus = try APIClient.decodeObject(data)
        return status.needInit ?? false
    }

    /// 登录。面板返回 401 时会带 `code`（如 `two_factor_required`），调用方按 code 决定后续流程。
    func login(username: String, password: String, totp: String?) async throws -> LoginResult {
        var body: [String: Any] = ["username": username, "password": password]
        if let totp, !totp.isEmpty { body["totp_code"] = totp }
        let data = try await send(path: "/auth/login",
                                  method: "POST",
                                  json: body,
                                  authorized: false,
                                  canRefresh: false)
        let result: LoginResult = try APIClient.decodeObject(data)
        storeTokens(access: result.accessToken, refresh: result.refreshToken)
        return result
    }

    func fetchCurrentUser() async throws -> PanelUser {
        let envelope: UserEnvelope = try await object("/auth/user")
        return envelope.user
    }

    func logout() async throws {
        _ = try await send(path: "/auth/logout", method: "POST", canRefresh: false)
    }

    /// 健康检查：不需要鉴权，用来判断「地址通不通」。
    func healthCheck() async throws -> HealthStatus {
        let data = try await send(path: "/health", authorized: false, canRefresh: false)
        return try APIClient.decodeObject(data)
    }

    /// 带鉴权的探活：能拿到当前用户就说明令牌仍然有效。
    func probeAuthorized() async throws -> PanelUser {
        try await fetchCurrentUser()
    }

    func panelVersion() async throws -> PanelVersion {
        let data = try await send(path: "/version", authorized: false, canRefresh: false)
        return try APIClient.decodeObject(data)
    }

    // MARK: - 概览

    func fetchDashboard(range: Int = 7) async throws -> PanelDashboard {
        try await object("/system/dashboard", query: ["range": "\(range)"])
    }

    // MARK: - 任务

    func fetchTasks(keyword: String = "",
                    status: String? = nil,
                    page: Int = 1,
                    pageSize: Int = 30) async throws -> PagedResult<PanelTask> {
        var query: [String: String] = [
            "page": "\(page)",
            "page_size": "\(pageSize)"
        ]
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { query["keyword"] = trimmed }
        if let status, !status.isEmpty { query["status"] = status }
        return try await list("/tasks", query: query)
    }

    func runTask(id: Int) async throws {
        _ = try await send(path: "/tasks/\(id)/run", method: "PUT")
    }

    func stopTask(id: Int) async throws {
        _ = try await send(path: "/tasks/\(id)/stop", method: "PUT")
    }

    func setTaskEnabled(id: Int, enabled: Bool) async throws {
        _ = try await send(path: "/tasks/\(id)/\(enabled ? "enable" : "disable")", method: "PUT")
    }

    func deleteTask(id: Int) async throws {
        _ = try await send(path: "/tasks/\(id)", method: "DELETE")
    }

    func createTask(_ draft: TaskDraft) async throws {
        _ = try await send(path: "/tasks", method: "POST", json: draft.json)
    }

    func updateTask(id: Int, draft: TaskDraft) async throws {
        _ = try await send(path: "/tasks/\(id)", method: "PUT", json: draft.json)
    }

    // MARK: - 日志

    func fetchLogs(taskId: Int? = nil,
                   status: Int? = nil,
                   keyword: String = "",
                   page: Int = 1,
                   pageSize: Int = 30) async throws -> PagedResult<TaskLog> {
        var query: [String: String] = [
            "page": "\(page)",
            "page_size": "\(pageSize)"
        ]
        if let taskId { query["task_id"] = "\(taskId)" }
        if let status { query["status"] = "\(status)" }
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { query["keyword"] = trimmed }
        return try await list("/logs", query: query)
    }

    func fetchLog(id: Int) async throws -> TaskLog {
        try await object("/logs/\(id)")
    }

    func fetchLatestLog(taskId: Int) async throws -> TaskLog {
        try await object("/tasks/\(taskId)/latest-log")
    }

    // MARK: - 环境变量

    func fetchEnvs() async throws -> [EnvVar] {
        // 面板把大于 100 的 page_size 直接降级成 20（实测 500 → 20），
        // 所以这里固定 100 并翻页拉全，否则变量多时只能看到前 20 个。
        try await fetchAll("/envs")
    }

    func createEnv(_ draft: EnvDraft) async throws {
        _ = try await send(path: "/envs", method: "POST", json: draft.json)
    }

    func updateEnv(id: Int, draft: EnvDraft) async throws {
        _ = try await send(path: "/envs/\(id)", method: "PUT", json: draft.json)
    }

    func deleteEnv(id: Int) async throws {
        _ = try await send(path: "/envs/\(id)", method: "DELETE")
    }

    func setEnvEnabled(id: Int, enabled: Bool) async throws {
        _ = try await send(path: "/envs/\(id)/\(enabled ? "enable" : "disable")", method: "PUT")
    }

    // MARK: - 订阅

    func fetchSubscriptions() async throws -> [PanelSubscription] {
        try await fetchAll("/subscriptions")
    }

    func pullSubscription(id: Int) async throws {
        _ = try await send(path: "/subscriptions/\(id)/pull", method: "PUT")
    }

    func setSubscriptionEnabled(id: Int, enabled: Bool) async throws {
        _ = try await send(path: "/subscriptions/\(id)/\(enabled ? "enable" : "disable")", method: "PUT")
    }

    /// `PUT /subscriptions/:id/pull/stop`：只对正在跑的拉取有效，否则 400「当前没有进行中的拉取任务」。
    func stopSubscriptionPull(id: Int) async throws {
        _ = try await send(path: "/subscriptions/\(id)/pull/stop", method: "PUT")
    }

    /// 订阅拉取的 SSE 流（`GET /subscriptions/:id/pull-stream`）。
    /// 面板在流里只发 `data: 一行输出`，结束时补一条 `event: done`。
    func subscriptionPullStreamRequest(id: Int) throws -> URLRequest {
        try streamRequest(path: "/subscriptions/\(id)/pull-stream")
    }

    // MARK: - 分页拉全

    /// 按 100 条一页翻到底。面板对 `page_size > 100` 的处理是**悄悄降级成 20**，
    /// 所以绝不能靠一个大 page_size 一次拉完。
    private func fetchAll<T: Decodable>(_ path: String, maxPages: Int = 50) async throws -> [T] {
        var all: [T] = []
        var page = 1
        while page <= maxPages {
            let result: PagedResult<T> = try await list(path, query: [
                "page": "\(page)",
                "page_size": "100"
            ])
            all.append(contentsOf: result.items)
            if result.items.isEmpty { break }
            if result.total > 0, all.count >= result.total { break }
            if result.items.count < 100 { break }
            page += 1
        }
        return all
    }

    // MARK: - 脚本

    func fetchScriptTree() async throws -> [ScriptNode] {
        let data = try await send(path: "/scripts/tree")
        if let envelope = try? APIClient.decoder.decode(DataEnvelope<[ScriptNode]>.self, from: data) {
            return envelope.data
        }
        if let nodes = try? APIClient.decoder.decode([ScriptNode].self, from: data) {
            return nodes
        }
        throw PanelError.decoding("脚本目录解析失败")
    }

    func fetchScriptContent(path: String) async throws -> ScriptContent {
        try await object("/scripts/content", query: ["path": path])
    }

    func saveScriptContent(path: String, content: String) async throws {
        _ = try await send(path: "/scripts/content",
                           method: "PUT",
                           json: ["path": path, "content": content])
    }

    /// 版本历史：面板每次保存都会留一个版本。
    func fetchScriptVersions(path: String) async throws -> [ScriptVersion] {
        let result: PagedResult<ScriptVersion> = try await list("/scripts/versions",
                                                               query: ["path": path])
        return result.items
    }

    /// 单个历史版本的内容（`GET /scripts/versions/:id`）。
    func fetchScriptVersion(id: Int) async throws -> ScriptVersionDetail {
        try await object("/scripts/versions/\(id)")
    }

    // MARK: - 在线运行

    /// 运行一个已保存的脚本文件，返回 run_id（用于轮询输出）。
    /// 传入 `content` 时会改成「运行这份内容」，不必先保存（面板支持 path + content + language 组合）。
    func runSavedScript(path: String,
                        content: String? = nil,
                        language: String? = nil) async throws -> String {
        var body: [String: Any] = [:]
        if !path.isEmpty { body["path"] = path }
        if let content, !content.isEmpty {
            body["content"] = content
            body["language"] = language ?? ScriptLanguage.detect(path: path) ?? "python"
        }
        let data = try await send(path: "/scripts/run", method: "POST", json: body)
        let payload: RunIDPayload = try APIClient.decodeObject(data)
        return payload.runId ?? ""
    }

    /// 运行一段临时代码（不落盘到脚本目录）。
    func runCode(_ code: String, language: String) async throws -> String {
        let data = try await send(path: "/scripts/run-code",
                                  method: "POST",
                                  json: ["code": code, "language": language])
        let payload: RunIDPayload = try APIClient.decodeObject(data)
        return payload.runId ?? ""
    }

    func debugLogs(runID: String) async throws -> DebugRunSnapshot {
        try await object("/scripts/run/\(escaped(runID))/logs")
    }

    func stopDebugRun(runID: String) async throws {
        _ = try await send(path: "/scripts/run/\(escaped(runID))/stop", method: "PUT")
    }

    func clearDebugRun(runID: String) async throws {
        _ = try await send(path: "/scripts/run/\(escaped(runID))", method: "DELETE")
    }

    // MARK: - Cron 工具

    /// 面板内置的模板列表（裸数组，没有 data 外壳）。
    func fetchCronTemplates() async throws -> [CronTemplate] {
        let data = try await send(path: "/tasks/cron/templates")
        if let list = try? APIClient.decoder.decode([CronTemplate].self, from: data) {
            return list
        }
        if let envelope = try? APIClient.decoder.decode(DataEnvelope<[CronTemplate]>.self, from: data) {
            return envelope.data
        }
        throw PanelError.decoding("Cron 模板解析失败")
    }

    /// 让面板解释表达式并算出下次执行时间。
    func parseCron(_ expression: String) async throws -> CronParseResult {
        let data = try await send(path: "/tasks/cron/parse",
                                  method: "POST",
                                  json: ["expression": expression])
        return try APIClient.decodeObject(data)
    }

    /// run_id 里可能带文件名，放路径前先转义。
    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct RunIDPayload: Decodable {
    var runId: String?
    var message: String?
}
