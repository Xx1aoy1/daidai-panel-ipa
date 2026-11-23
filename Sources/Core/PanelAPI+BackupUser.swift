import Foundation

// 备份恢复（`/system/backup*`、`/system/restore*`）与用户管理（`/users`）。
// 两组接口在面板侧都是 `RequireAdmin()`，operator / viewer 一律 403。
extension APIClient {

    // MARK: - 备份列表与创建

    /// `GET /system/backups`：目录为空时面板回 `{"data":null}`，这里按空数组兜。
    func fetchBackups() async throws -> [PanelBackup] {
        let data = try await send(path: "/system/backups")
        if let envelope = try? Self.decoder.decode(OptionalListEnvelope<PanelBackup>.self, from: data) {
            return envelope.data ?? []
        }
        if let items = try? Self.decoder.decode([PanelBackup].self, from: data) {
            return items
        }
        return []
    }

    /// `POST /system/backup`：`password` 非空时服务端写 `.enc`，否则写 `.tgz`。
    /// `name` 留空由服务端按 `backup_yyyyMMdd_HHmmss` 命名。
    func createBackup(name: String, password: String, selection: BackupSelection) async throws -> BackupCreateResult {
        var payload: [String: Any] = ["selection": selection.jsonObject]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { payload["name"] = trimmedName }
        if !password.isEmpty { payload["password"] = password }
        let data = try await send(path: "/system/backup", method: "POST", json: payload)
        return try Self.decoder.decode(BackupCreateResult.self, from: data)
    }

    func deleteBackup(filename: String) async throws -> String? {
        let data = try await send(path: "/system/backup", method: "DELETE", query: ["filename": filename])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 备份下载：接口要 Authorization（不像原始日志那样给一次性票据），
    /// 所以走带鉴权的长耗时会话，拿到字节后落到临时目录再交给分享面板。
    func downloadBackup(filename: String) async throws -> URL {
        let result = try await downloadBinary(path: "/system/backup/download", query: ["filename": filename])
        let safeName = (result.filename ?? filename).replacingOccurrences(of: "/", with: "_")
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "backup.tgz" : safeName)
        try? FileManager.default.removeItem(at: target)
        try result.data.write(to: target, options: .atomic)
        return target
    }

    /// 上传备份文件。面板先落临时文件、校验内容通过才改名，同名会自动加 `-1` 后缀。
    /// 返回服务端实际保存的文件名。
    func uploadBackup(fileURL: URL) async throws -> String? {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let raw = try await uploadMultipart(path: "/system/backup/upload",
                                            field: "file",
                                            filename: fileURL.lastPathComponent,
                                            mimeType: Self.mimeType(for: fileURL.lastPathComponent),
                                            fileData: data)
        let envelope = try? Self.decoder.decode(BackupUploadEnvelope.self, from: raw)
        return envelope?.data?.filename
    }

    // MARK: - 恢复

    /// `POST /system/restore` 是同步阻塞的整库替换，可能要几分钟，用长超时会话。
    /// 注意：恢复会覆盖用户表，成功后当前登录态基本作废，界面要引导重新登录。
    func restoreBackup(filename: String, password: String) async throws -> String? {
        var payload: [String: Any] = ["filename": filename]
        if !password.isEmpty { payload["password"] = password }
        let data = try await sendLongRunning(path: "/system/restore", method: "POST", json: payload)
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    func fetchRestoreProgress() async throws -> RestoreProgress {
        try await object("/system/restore/progress")
    }

    /// 恢复后建议重启一次，让运行时按新配置重新加载。
    func restartPanel() async throws {
        _ = try await send(path: "/system/restart", method: "POST")
    }

    // MARK: - 用户管理

    /// `GET /users`：`{data:[...]}`，不是分页结构。
    func fetchUsers() async throws -> [PanelAccount] {
        let data = try await send(path: "/users")
        if let envelope = try? Self.decoder.decode(OptionalListEnvelope<PanelAccount>.self, from: data) {
            return envelope.data ?? []
        }
        return try Self.decoder.decode([PanelAccount].self, from: data)
    }

    /// `POST /users` 回 201，`message` 与 `data` 平级。
    func createUser(username: String, password: String, role: PanelRole) async throws -> PanelAccount? {
        let data = try await send(path: "/users",
                                  method: "POST",
                                  json: ["username": username, "password": password, "role": role.rawValue])
        return (try? Self.decoder.decode(AccountResult.self, from: data))?.data
    }

    /// `PUT /users/:id`：只传要改的字段。面板改完会撤销该用户的全部会话。
    func updateUser(id: Int, role: PanelRole?, enabled: Bool?) async throws -> PanelAccount? {
        var payload: [String: Any] = [:]
        if let role { payload["role"] = role.rawValue }
        if let enabled { payload["enabled"] = enabled }
        let data = try await send(path: "/users/\(id)", method: "PUT", json: payload)
        return (try? Self.decoder.decode(AccountResult.self, from: data))?.data
    }

    func deleteUser(id: Int) async throws -> String? {
        let data = try await send(path: "/users/\(id)", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 重置密码会清掉该用户的通行密钥并撤销会话（面板侧行为）。
    func resetUserPassword(id: Int, password: String) async throws -> String? {
        let data = try await send(path: "/users/\(id)/reset-password",
                                  method: "PUT",
                                  json: ["password": password])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - 辅助

    private static func mimeType(for filename: String) -> String {
        let lowered = filename.lowercased()
        if lowered.hasSuffix(".json") { return "application/json" }
        if lowered.hasSuffix(".enc") { return "application/octet-stream" }
        if lowered.hasSuffix(".tgz") || lowered.hasSuffix(".tar.gz") { return "application/gzip" }
        return "application/octet-stream"
    }
}

/// 列表接口的 `data` 允许为 null（面板在目录为空时就是这么回的）。
private struct OptionalListEnvelope<T: Decodable>: Decodable {
    var data: [T]?
}

/// `POST /users` 与 `PUT /users/:id` 的回执：`{message, data:{...}}`。
private struct AccountResult: Decodable {
    var message: String?
    var data: PanelAccount?
}

/// `POST /system/backup/upload` 的回执：`{message, data:{filename}}`。
private struct BackupUploadEnvelope: Decodable {
    var message: String?
    var data: BackupUploadPayload?

    struct BackupUploadPayload: Decodable {
        var filename: String?
    }
}
