import Foundation

// 管理员（admin）专属能力的接口映射。
//
// 这些接口在面板侧统一挂了 `middleware.RequireAdmin()`，operator / viewer 一律 403：
// 通知渠道（含密钥）、系统信息与健康检查、日志删除与原始下载、脚本格式化。
// 客户端在入口处用 `session.user?.isAdmin` 先挡一层，避免点进去吃 403。
extension APIClient {

    // MARK: - 通知渠道

    /// `GET /notifications` 返回 `{data: [...]}`，不是分页结构。
    func fetchNotifyChannels() async throws -> [NotifyChannel] {
        let data = try await send(path: "/notifications")
        if let envelope = try? Self.decoder.decode(DataEnvelope<[NotifyChannel]>.self, from: data) {
            return envelope.data
        }
        return try Self.decoder.decode([NotifyChannel].self, from: data)
    }

    /// 渠道类型注册表：19 种渠道的字段定义，用来动态生成表单。
    func fetchNotifyTypes() async throws -> [NotifyChannelType] {
        let data = try await send(path: "/notifications/types")
        if let envelope = try? Self.decoder.decode(DataEnvelope<[NotifyChannelType]>.self, from: data) {
            return envelope.data
        }
        return try Self.decoder.decode([NotifyChannelType].self, from: data)
    }

    /// 面板要求 `config` 是 JSON 字符串，且值全是字符串（数字/布尔会让该渠道所有推送失败）。
    func createNotifyChannel(_ draft: NotifyDraft) async throws -> NotifyChannel? {
        let data = try await send(path: "/notifications", method: "POST", json: draft.createJSON)
        // 201 回执是 `{message, data: {...}}`，不是 `{data: {message, data}}`，
        // 所以这里直接按平铺结构解，绕开 decodeObject 的包装优先策略。
        let result = try? Self.decoder.decode(NotifyChannelCreateResult.self, from: data)
        return result?.data
    }

    func updateNotifyChannel(id: Int, draft: NotifyDraft) async throws {
        _ = try await send(path: "/notifications/\(id)", method: "PUT", json: draft.updateJSON)
    }

    func setNotifyChannelEnabled(id: Int, enabled: Bool) async throws {
        _ = try await send(path: "/notifications/\(id)/\(enabled ? "enable" : "disable")", method: "PUT")
    }

    /// 发一条真实测试消息（「呆呆面板测试通知」），成功/失败都会写回渠道的 last_test_status。
    func testNotifyChannel(id: Int) async throws {
        _ = try await send(path: "/notifications/\(id)/test", method: "POST")
    }

    func deleteNotifyChannel(id: Int) async throws {
        _ = try await send(path: "/notifications/\(id)", method: "DELETE")
    }

    // MARK: - 系统

    func fetchSystemInfo() async throws -> PanelSystemInfo {
        try await object("/system/info")
    }

    /// 健康检查。注意这个接口没有 `data` 外壳，直接返回 `{items, last_checked_at}`。
    func fetchHealthCheck() async throws -> HealthCheckResult {
        let data = try await send(path: "/system/health-check")
        return try Self.decoder.decode(HealthCheckResult.self, from: data)
    }

    /// 触发一次完整的主动体检（`POST /system/health-check`），比 GET 更慢但结果更新。
    func runHealthCheck() async throws -> HealthCheckResult {
        let data = try await send(path: "/system/health-check", method: "POST")
        return try Self.decoder.decode(HealthCheckResult.self, from: data)
    }

    // MARK: - 日志管理

    func deleteLog(id: Int) async throws {
        _ = try await send(path: "/logs/\(id)", method: "DELETE")
    }

    /// 批量删除。面板同时挂了 `DELETE /logs/batch` 和 `POST /logs/batch-delete`，这里用后者。
    func batchDeleteLogs(ids: [Int]) async throws -> String? {
        let data = try await send(path: "/logs/batch-delete", method: "POST", json: ["ids": ids])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 清理 N 天前的日志（记录 + 磁盘文件一起删）。`days` 缺省时由面板读配置 `log_retention_days`。
    func cleanLogs(days: Int?) async throws -> String? {
        let query = days.map { ["days": "\($0)"] } ?? [:]
        let data = try await send(path: "/logs/clean", method: "DELETE", query: query)
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 取原始日志下载票据（120 秒有效、一次性）。返回的 url 是相对路径。
    func fetchRawLogTicket(id: Int) async throws -> RawLogTicket {
        try await object("/logs/\(id)/raw-ticket")
    }

    /// 拼成绝对下载地址。票据已自带鉴权，不要再加 Authorization 头。
    func rawLogURL(_ ticket: RawLogTicket) -> URL? {
        guard let path = URL(string: ticket.url)?.path,
              let query = URL(string: ticket.url)?.query
        else { return nil }
        var base = rootURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var text = base + path
        if let query, !query.isEmpty { text += "?" + query }
        return URL(string: text)
    }

    /// 下载原始日志到临时文件，返回本地路径（供分享/预览用）。
    func downloadRawLog(id: Int) async throws -> URL {
        let ticket = try await fetchRawLogTicket(id: id)
        guard let url = rawLogURL(ticket) else { throw PanelError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("app", forHTTPHeaderField: "X-Client-Type")
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PanelError.transport("原始日志下载失败（HTTP \(status)）")
        }

        let safeName = (ticket.filename ?? "log-\(id).log")
            .replacingOccurrences(of: "/", with: "_")
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "log-\(id).log" : safeName)
        try data.write(to: target, options: .atomic)
        return target
    }

    // MARK: - 脚本格式化

    /// 面板按语言调用 black / autopep8（python）、shfmt（shell）、gofmt（go）、以及内置 JSON 美化。
    /// 没装对应工具时原样返回，`formatter` 为 "none"。
    func formatScript(content: String, language: String) async throws -> FormatResult {
        let data = try await send(path: "/scripts/format",
                                  method: "POST",
                                  json: ["content": content, "language": language])
        return try Self.decodeObject(data)
    }
}

/// `POST /notifications` 的 201 回执：`{message, data: {...}}`。
private struct NotifyChannelCreateResult: Decodable {
    var message: String?
    var data: NotifyChannel?
}
