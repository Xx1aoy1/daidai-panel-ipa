import Foundation

/// 一条登录日志（`GET /security/login-logs`，需要 admin）。
///
/// 面板的 `status` 只有两态：`0` 成功 / `1` 失败。
/// `client_type` 是按 UserAgent 现推的（`web` / `app`），
/// 而 `client_name` 优先用登录时客户端自己报的名字（`X-Device-Model` 那些头）。
struct LoginLogEntry: Decodable, Identifiable, Equatable {
    let id: Int
    let userId: Int?
    let username: String?
    let ip: String?
    let clientName: String?
    let userAgent: String?
    let method: String?
    let status: Int?
    let message: String?
    let createdAt: String?
    let clientType: String?
    let clientTypeLabel: String?

    var isSuccess: Bool { (status ?? 0) == 0 }

    var usernameText: String {
        let value = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未知用户" : value
    }

    var ipText: String {
        let value = ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
    }

    var methodText: String {
        let value = method?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "密码登录" : value
    }

    var clientText: String {
        if let name = clientName, !name.isEmpty { return name }
        if let label = clientTypeLabel, !label.isEmpty { return label }
        return "未知客户端"
    }

    var messageText: String {
        let value = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? (isSuccess ? "登录成功" : "登录失败") : value
    }

    var timeText: String {
        DateText.relative(createdAt)
    }

    var detailTimeText: String {
        guard let date = DateParser.parse(createdAt) else { return "—" }
        return DateText.total(date)
    }
}

/// 一个仍然有效（access 或 refresh 未过期）的会话。
///
/// 面板给 admin 返回的是**所有人的会话**（不分账号），`current` 按会话号判定，
/// 所以列表里可能出现别的用户名。`current` 为真的那行就是当前这台设备。
struct PanelSession: Decodable, Identifiable, Equatable {
    let id: Int
    let userId: Int?
    let username: String?
    let clientType: String?
    let clientTypeLabel: String?
    let clientName: String?
    let ip: String?
    let userAgent: String?
    let createdAt: String?
    let expiresAt: String?
    let current: Bool?

    var isCurrent: Bool { current ?? false }

    var usernameText: String {
        let value = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未知用户" : value
    }

    var deviceText: String {
        if let name = clientName, !name.isEmpty { return name }
        if let label = clientTypeLabel, !label.isEmpty { return label }
        return clientType == "app" ? "APP 端" : "网页端"
    }

    var ipText: String {
        let value = ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
    }

    var createdText: String {
        DateText.relative(createdAt)
    }

    /// 过期时间用绝对时间更直观：会话被顶掉通常在「到期」之前就发生了。
    var expiresText: String {
        guard let date = DateParser.parse(expiresAt) else { return "—" }
        return DateText.absolute(date)
    }

    var isAppClient: Bool { (clientType ?? "") == "app" }
}

/// IP 白名单条目（`GET /security/ip-whitelist`）。
struct IPWhitelistEntry: Decodable, Identifiable, Equatable {
    let id: Int
    let ip: String
    let remarks: String?
    let createdAt: String?

    var remarksText: String {
        let value = remarks?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未填写描述" : value
    }

    var createdText: String {
        guard let date = DateParser.parse(createdAt) else { return "—" }
        return DateText.total(date)
    }
}

/// `GET /security/login-stats?days=N` 的统计块（N 只接受 1-90，越界回落到 7）。
struct LoginStats: Decodable {
    let totalLogins: Int?
    let successLogins: Int?
    let failedLogins: Int?
    let activeSessions: Int?
    let lockedAccounts: Int?
    let periodDays: Int?

    var days: Int { periodDays ?? 7 }
    var total: Int { totalLogins ?? 0 }
    var success: Int { successLogins ?? 0 }
    var failed: Int { failedLogins ?? 0 }
    var sessions: Int { activeSessions ?? 0 }
    var locked: Int { lockedAccounts ?? 0 }
}

/// `GET /security/2fa/status`。
struct TwoFactorStatus: Decodable {
    let enabled: Bool?
    var isEnabled: Bool { enabled ?? false }
}

/// `POST /security/2fa/setup`：只发密钥和 otpauth 链接，二维码要客户端自己画。
///
/// 注意这个接口**不改变启用状态**，密钥要先经过 `POST /security/2fa/verify` 验码才算绑定成功。
/// 而且一旦已启用，再调 setup 会被面板拒绝（400「两步验证已启用，如需重新绑定请先关闭」）。
struct TwoFactorSetup: Decodable {
    let secret: String
    let uri: String
}
