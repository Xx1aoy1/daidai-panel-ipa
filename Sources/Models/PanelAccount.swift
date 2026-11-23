import Foundation

/// `GET /users` 里的一条账号记录（需要 admin）。
struct PanelAccount: Decodable, Identifiable, Equatable {
    let id: Int
    let username: String
    let role: String?
    let enabled: Bool?
    let avatarUrl: String?
    let lastLoginAt: String?
    let createdAt: String?
    let updatedAt: String?
    let twoFactorEnabled: Bool?

    var roleValue: PanelRole { PanelRole(rawValue: role ?? "") ?? .viewer }

    var isEnabled: Bool { enabled ?? true }

    var initial: String {
        guard let first = username.first else { return "?" }
        return String(first).uppercased()
    }

    var lastLoginText: String {
        guard let lastLoginAt, !lastLoginAt.isEmpty else { return "从未登录" }
        return DateText.relative(lastLoginAt)
    }

    var createdText: String {
        guard let date = DateParser.parse(createdAt) else { return "—" }
        return DateText.total(date)
    }

    /// 面板的「改角色 / 禁用 / 重置密码 / 删除」都会顺手撤销该用户的全部会话，
    /// 所以这些操作的确认文案里要提前说清楚：对方会被踢下线。
    var needsSessionWarning: Bool { isEnabled }
}

enum PanelRole: String, CaseIterable, Identifiable {
    case admin
    case operator
    case viewer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: return "管理员"
        case .operator: return "运维"
        case .viewer: return "只读"
        }
    }

    var detail: String {
        switch self {
        case .admin: return "全部权限，含系统设置、通知、依赖、备份、用户管理"
        case .operator: return "可读写任务、变量、订阅、脚本；管理类接口 403"
        case .viewer: return "只能看任务与日志，写操作与变量/脚本/订阅均 403"
        }
    }

    var icon: String {
        switch self {
        case .admin: return "crown.fill"
        case .operator: return "wrench.and.screwdriver.fill"
        case .viewer: return "eye.fill"
        }
    }
}

/// 面板的账号规则，客户端先校验一遍，省得来回吃 400。
///
/// 服务端口径（server/pkg/validator）：
/// - 用户名 1-32 位，中文 / 字母 / 数字 / 下划线；
/// - 新密码至少 8 个字符、UTF-8 不超过 72 字节（bcrypt 硬限制），
///   字母 / 数字 / 符号三类里至少含两类。
enum AccountRules {
    static func validateUsername(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "用户名不能为空" }
        if name.count > 32 { return "用户名最多 32 位" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        for scalar in name.unicodeScalars {
            if allowed.contains(scalar) { continue }
            if scalar.properties.isIdeographic { continue }
            return "用户名只能包含中文、字母、数字和下划线"
        }
        return nil
    }

    static func validatePassword(_ password: String) -> String? {
        if password.count < 8 { return "密码至少 8 位" }
        if password.utf8.count > 72 {
            return "密码过长：UTF-8 编码不能超过 72 字节（一个汉字占 3 字节）"
        }
        var hasLetter = false
        var hasDigit = false
        var hasOther = false
        for character in password {
            if character.isLetter {
                hasLetter = true
            } else if character.isNumber {
                hasDigit = true
            } else {
                hasOther = true
            }
        }
        let kinds = [hasLetter, hasDigit, hasOther].filter { $0 }.count
        if kinds < 2 { return "密码需包含字母、数字、符号中的至少两种" }
        return nil
    }
}
