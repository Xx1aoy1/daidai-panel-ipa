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

/// 一条安全审计（`GET /security/audit-logs`，需要 admin）。
///
/// 面板只记录**成功**的敏感操作：改密码、开关 2FA、增删通行密钥、建删用户、建恢复备份、
/// 执行系统命令、改配置、动 IP 白名单、清空登录日志……失败的操作不写。
/// `action` 是稳定的英文标识（见 `SecurityAuditAction`），`detail` 是人话描述。
struct SecurityAuditEntry: Decodable, Identifiable, Equatable {
    let id: Int
    let userId: Int?
    let username: String?
    let action: String?
    let detail: String?
    let ip: String?
    let createdAt: String?

    var actionCode: String { action ?? "" }
    var actionLabel: String { SecurityAuditAction.label(for: actionCode) }
    var risk: SecurityAuditRisk { SecurityAuditAction.risk(for: actionCode) }

    /// 应用令牌（开放 API）的操作者形如 `应用:名称（app_key）`，原样展示即可。
    var actorText: String {
        let value = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未知操作者" : value
    }

    var detailText: String {
        let value = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
    }

    var ipText: String {
        let value = ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
    }

    var timeText: String { DateText.relative(createdAt) }

    var fullTimeText: String {
        guard let date = DateParser.parse(createdAt) else { return "—" }
        return DateText.total(date)
    }
}

/// 审计动作的风险档位，只用于给标签上色：
/// 销毁/覆盖数据的标红，改系统状态的标黄，其余中性。
enum SecurityAuditRisk {
    case normal
    case warning
    case danger
}

/// 面板 `server/service/login_security.go` 里的 `Audit*` 常量，翻成中文。
///
/// 服务端新增标识时要回来补一条；没收录的标识原样显示，不至于整行空白。
enum SecurityAuditAction: String, CaseIterable, Identifiable {
    case passwordChange = "password.change"
    case usernameChange = "username.change"
    case twoFactorEnable = "2fa.enable"
    case twoFactorDisable = "2fa.disable"
    case passkeyAdd = "passkey.add"
    case passkeyDelete = "passkey.delete"
    case userCreate = "user.create"
    case userUpdate = "user.update"
    case userDelete = "user.delete"
    case userPasswordReset = "user.password_reset"
    case backupCreate = "backup.create"
    case backupUpload = "backup.upload"
    case backupDownload = "backup.download"
    case backupRestore = "backup.restore"
    case backupDelete = "backup.delete"
    case consoleRun = "console.run"
    case configUpdate = "config.update"
    case configDelete = "config.delete"
    case configScriptUpdate = "config_script.update"
    case openAppCreate = "open_app.create"
    case openAppDelete = "open_app.delete"
    case openAppResetSecret = "open_app.reset_secret"
    case openAppScopeChange = "open_app.scope_change"
    case ipWhitelistAdd = "ip_whitelist.add"
    case ipWhitelistRemove = "ip_whitelist.remove"
    case loginLogsClear = "login_logs.clear"
    case sshKeyCreate = "ssh_key.create"
    case sshKeyDelete = "ssh_key.delete"
    case systemUpdate = "system.update"
    case systemRestart = "system.restart"
    case systemStop = "system.stop"
    case processKill = "process.kill"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .passwordChange: return "修改密码"
        case .usernameChange: return "修改用户名"
        case .twoFactorEnable: return "开启两步验证"
        case .twoFactorDisable: return "关闭两步验证"
        case .passkeyAdd: return "添加通行密钥"
        case .passkeyDelete: return "删除通行密钥"
        case .userCreate: return "新建用户"
        case .userUpdate: return "修改用户"
        case .userDelete: return "删除用户"
        case .userPasswordReset: return "重置用户密码"
        case .backupCreate: return "创建备份"
        case .backupUpload: return "上传备份"
        case .backupDownload: return "下载备份"
        case .backupRestore: return "恢复备份"
        case .backupDelete: return "删除备份"
        case .consoleRun: return "执行系统命令"
        case .configUpdate: return "修改系统配置"
        case .configDelete: return "删除系统配置"
        case .configScriptUpdate: return "修改 config.sh"
        case .openAppCreate: return "新建开放 API 应用"
        case .openAppDelete: return "删除开放 API 应用"
        case .openAppResetSecret: return "重置应用密钥"
        case .openAppScopeChange: return "修改应用权限"
        case .ipWhitelistAdd: return "添加 IP 白名单"
        case .ipWhitelistRemove: return "删除 IP 白名单"
        case .loginLogsClear: return "清空登录日志"
        case .sshKeyCreate: return "添加 SSH 密钥"
        case .sshKeyDelete: return "删除 SSH 密钥"
        case .systemUpdate: return "更新面板"
        case .systemRestart: return "重启面板"
        case .systemStop: return "停止面板"
        case .processKill: return "结束后台进程"
        }
    }

    var risk: SecurityAuditRisk {
        switch self {
        case .userDelete, .backupDelete, .configDelete, .openAppDelete, .ipWhitelistRemove,
             .loginLogsClear, .sshKeyDelete, .passkeyDelete, .backupRestore, .userPasswordReset,
             .openAppResetSecret, .twoFactorDisable, .processKill, .consoleRun, .systemStop:
            return .danger
        case .systemUpdate, .systemRestart:
            return .warning
        default:
            return .normal
        }
    }

    static func label(for code: String) -> String {
        guard !code.isEmpty else { return "未知操作" }
        return SecurityAuditAction(rawValue: code)?.label ?? code
    }

    static func risk(for code: String) -> SecurityAuditRisk {
        SecurityAuditAction(rawValue: code)?.risk ?? .normal
    }
}

/// 一枚通行密钥（`GET /security/passkeys`，只列**自己的**，任何角色都能调）。
///
/// 面板只给 id / name / rp_id / origin / 时间 / backup_state，公钥、凭据、userHandle 都不外传。
/// 注意：每枚凭据绑定添加时的来源（scheme + 主机 + 端口），换成 IP、换端口访问都用不了这一枚；
/// 而且通行密钥登录会**跳过两步验证**，所以删之前要确认自己还记得密码。
struct PasskeyEntry: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String?
    let rpId: String?
    let origin: String?
    let createdAt: String?
    let lastUsedAt: String?
    let backupState: Bool?

    var nameText: String {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "通行密钥" : value
    }

    /// 来源按「主机:端口」显示：同域名换端口就算另一个来源，只给域名容易误导。
    var hostText: String {
        if let origin, let url = URL(string: origin), let host = url.host {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        let value = rpId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未知来源" : value
    }

    /// 凭据是否被系统密码管理器同步（iCloud 钥匙串 / 谷歌密码管理器）。
    var isSynced: Bool { backupState ?? false }

    var createdText: String {
        guard let date = DateParser.parse(createdAt) else { return "—" }
        return DateText.absolute(date)
    }

    var lastUsedText: String {
        guard let date = DateParser.parse(lastUsedAt) else { return "从未使用" }
        return DateText.relative(date)
    }
}
