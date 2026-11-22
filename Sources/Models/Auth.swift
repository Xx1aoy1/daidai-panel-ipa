import Foundation

struct PanelUser: Decodable, Identifiable, Equatable {
    let id: Int
    let username: String?
    let role: String?
    let avatarUrl: String?
    let nickname: String?
    let email: String?
    let createdAt: String?

    var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return username ?? "未命名用户"
    }

    var roleText: String {
        switch role ?? "" {
        case "admin": return "管理员"
        case "operator": return "运维"
        case "viewer": return "只读"
        default: return role ?? "用户"
        }
    }

    var isAdmin: Bool { (role ?? "") == "admin" }
}

struct LoginResult: Decodable {
    let message: String?
    let accessToken: String?
    let refreshToken: String?
    let user: PanelUser?
}

struct RefreshPayload: Decodable {
    let accessToken: String
}

struct UserEnvelope: Decodable {
    let user: PanelUser
}

struct InitStatus: Decodable {
    let needInit: Bool?
}

struct PanelVersion: Decodable {
    let version: String?
    let apiVersion: String?
    let framework: String?
}
