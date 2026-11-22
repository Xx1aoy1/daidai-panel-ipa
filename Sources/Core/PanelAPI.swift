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
        let result: PagedResult<EnvVar> = try await list("/envs", query: ["page": "1", "page_size": "500"])
        return result.items
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
        let result: PagedResult<PanelSubscription> = try await list("/subscriptions", query: ["page": "1", "page_size": "200"])
        return result.items
    }

    func pullSubscription(id: Int) async throws {
        _ = try await send(path: "/subscriptions/\(id)/pull", method: "PUT")
    }

    func setSubscriptionEnabled(id: Int, enabled: Bool) async throws {
        _ = try await send(path: "/subscriptions/\(id)/\(enabled ? "enable" : "disable")", method: "PUT")
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
}
