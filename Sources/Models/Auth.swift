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

    /// viewer 在面板里是纯只读：任务增删改、跑任务、环境变量、订阅、脚本全部 403。
    var isViewer: Bool { (role ?? "") == "viewer" }

    /// 能不能做写操作（新建/编辑/运行/启停/删除）。
    var canWrite: Bool {
        switch role ?? "" {
        case "admin", "operator": return true
        case "viewer": return false
        default: return true   // 未知角色交给服务端判定，别在客户端提前拦
        }
    }
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
