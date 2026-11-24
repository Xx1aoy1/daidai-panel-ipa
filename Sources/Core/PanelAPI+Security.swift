import Foundation

// 安全中心（`/security/*`）。
//
// 权限分两档（面板侧实测 + 源码确认）：
// - 登录日志 / 会话 / IP 白名单 / 审计日志 / 登录统计：`RequireAdmin()`，operator、viewer 一律 403；
// - 两步验证（`/security/2fa*`）：只认当前登录用户，任何角色都能管自己的。
extension APIClient {

    // MARK: - 登录日志

    /// `GET /security/login-logs?page=&page_size=&username=`。
    ///
    /// - `username` 是**精确匹配**（面板里就是 `Where("username = ?")`），不是模糊搜索；
    /// - `page_size` 超过 100 会被静默降级成 20，这里固定用 30。
    /// - 返回口径是标准分页：`{data, total, page, page_size}`。
    func fetchLoginLogs(page: Int = 1, pageSize: Int = 30, username: String? = nil) async throws -> PagedResult<LoginLogEntry> {
        var query = ["page": "\(max(page, 1))", "page_size": "\(min(max(pageSize, 1), 100))"]
        if let username {
            let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { query["username"] = trimmed }
        }
        return try await list("/security/login-logs", query: query)
    }

    /// `DELETE /security/login-logs`：**清空全部**登录日志（面板没有「只清 N 天前」的入参）。
    /// 返回体里带被清掉的条数，例如 `已清除 18 条登录日志`。
    func clearLoginLogs() async throws -> String? {
        let data = try await send(path: "/security/login-logs", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// `GET /security/login-stats?days=`：`days` 只接受 1-90，越界由面板回落到 7。
    func fetchLoginStats(days: Int = 7) async throws -> LoginStats {
        try await object("/security/login-stats", query: ["days": "\(min(max(days, 1), 90))"])
    }

    // MARK: - 会话

    /// `GET /security/sessions`：admin 能看到**所有人**的会话，`current` 标记按会话号判定。
    func fetchSessions() async throws -> [PanelSession] {
        let data = try await send(path: "/security/sessions")
        if let envelope = try? Self.decoder.decode(SecurityListEnvelope<PanelSession>.self, from: data) {
            return envelope.data ?? []
        }
        return try Self.decoder.decode([PanelSession].self, from: data)
    }

    /// `DELETE /security/sessions/:id`：撤销指定会话。
    /// 撤销的如果正好是当前会话，下一次请求就会 401 `session_revoked`，界面要提前提示。
    func revokeSession(id: Int) async throws -> String? {
        let data = try await send(path: "/security/sessions/\(id)", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// `DELETE /security/sessions/others`：撤销**当前用户**除当前会话以外的全部会话。
    /// 注意它按登录名找用户，跟列表里是否有别人的会话无关，也不会影响别人。
    func revokeOtherSessions() async throws -> String? {
        let data = try await send(path: "/security/sessions/others", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// `DELETE /security/sessions/user/:user_id`：把某个账号的会话全部踢掉（admin 才能调）。
    func revokeAllSessions(userID: Int) async throws -> String? {
        let data = try await send(path: "/security/sessions/user/\(userID)", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - IP 白名单

    /// `GET /security/ip-whitelist`：**列表非空就等于开启限制**，
    /// 空列表表示不限制（面板里没有单独的开关位）。
    func fetchIPWhitelist() async throws -> [IPWhitelistEntry] {
        let data = try await send(path: "/security/ip-whitelist")
        if let envelope = try? Self.decoder.decode(SecurityListEnvelope<IPWhitelistEntry>.self, from: data) {
            return envelope.data ?? []
        }
        return try Self.decoder.decode([IPWhitelistEntry].self, from: data)
    }

    /// `POST /security/ip-whitelist` → **201** + `{message, data:{...}}`。
    ///
    /// 支持单 IP、CIDR 网段和 IPv4 通配（`203.0.113.*`），格式由服务端规范化。
    /// 添加成功后立即生效：不在列表里的 IP **再也登不进来**（已登录的会话不受影响）。
    func addIPWhitelist(ip: String, remarks: String) async throws -> IPWhitelistEntry? {
        let trimmedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemarks = remarks.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await send(path: "/security/ip-whitelist",
                                  method: "POST",
                                  json: ["ip": trimmedIP, "remarks": trimmedRemarks])
        return (try? Self.decoder.decode(IPWhitelistResult.self, from: data))?.data
    }

    func removeIPWhitelist(id: Int) async throws -> String? {
        let data = try await send(path: "/security/ip-whitelist/\(id)", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - 两步验证（只作用于自己的账号）

    func fetchTwoFactorStatus() async throws -> TwoFactorStatus {
        try await object("/security/2fa/status")
    }

    /// `POST /security/2fa/setup`：只下发密钥与 otpauth 链接，**不会启用**。
    /// 已启用时面板回 400「两步验证已启用，如需重新绑定请先关闭」。
    func setupTwoFactor() async throws -> TwoFactorSetup {
        let data = try await send(path: "/security/2fa/setup", method: "POST")
        return try Self.decodeObject(data)
    }

    /// `POST /security/2fa/verify {code}`：验码通过才真正启用。
    func verifyTwoFactor(code: String) async throws -> String? {
        let data = try await send(path: "/security/2fa/verify",
                                  method: "POST",
                                  json: ["code": code])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// `DELETE /security/2fa`，**必须**带当前动态码（请求体 `{code}`）。
    /// 缺码回 400「请输入当前的动态验证码」，码错回 400「动态验证码错误」。
    func disableTwoFactor(code: String) async throws -> String? {
        let data = try await send(path: "/security/2fa",
                                  method: "DELETE",
                                  json: ["code": code])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - 安全审计（admin）

    /// `GET /security/audit-logs?page=&page_size=&action=`。
    ///
    /// - `action` 是**精确匹配**（`Where("action = ?")`），传空等于不过滤；
    /// - `page_size` 上限 100，越界由面板回落成 20，这里固定 30。
    func fetchAuditLogs(page: Int = 1,
                        pageSize: Int = 30,
                        action: SecurityAuditAction? = nil) async throws -> PagedResult<SecurityAuditEntry> {
        var query = ["page": "\(max(page, 1))", "page_size": "\(min(max(pageSize, 1), 100))"]
        if let action { query["action"] = action.rawValue }
        return try await list("/security/audit-logs", query: query)
    }

    // MARK: - 通行密钥（只作用于自己的账号）

    /// `GET /security/passkeys`：只列当前登录用户的，任何角色都能调。
    /// 只能看/改/删，**不能在这里新增**：注册要跑 WebAuthn，面板只做了网页端。
    func fetchPasskeys() async throws -> [PasskeyEntry] {
        let data = try await send(path: "/security/passkeys")
        if let envelope = try? Self.decoder.decode(SecurityListEnvelope<PasskeyEntry>.self, from: data) {
            return envelope.data ?? []
        }
        return try Self.decoder.decode([PasskeyEntry].self, from: data)
    }

    /// `PUT /security/passkeys/:id {name}`：名称会 trim 并截到 64 字，空名由面板回落成「通行密钥」。
    /// 不是自己的与不存在同样回 404，不透露别人的通行密钥是否存在。
    func renamePasskey(id: Int, name: String) async throws -> String? {
        let data = try await send(path: "/security/passkeys/\(id)",
                                  method: "PUT",
                                  json: ["name": name.trimmingCharacters(in: .whitespacesAndNewlines)])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// `DELETE /security/passkeys/:id`：删掉自己的一枚通行密钥，不可恢复（要重新在网页端注册）。
    func deletePasskey(id: Int) async throws -> String? {
        let data = try await send(path: "/security/passkeys/\(id)", method: "DELETE")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }
}

/// 安全类列表接口的 `data` 允许为 null（白名单 / 会话为空时），单独兜一层。
private struct SecurityListEnvelope<T: Decodable>: Decodable {
    var data: [T]?
}

/// `POST /security/ip-whitelist` 的回执：`{message, data:{...}}`（201）。
private struct IPWhitelistResult: Decodable {
    var message: String?
    var data: IPWhitelistEntry?
}
