import Foundation

/// 统一的错误类型：把面板返回的 `{"error": "...", "code": "..."}` 翻译成可展示的错误。
enum PanelError: LocalizedError, Equatable {
    case invalidURL
    case transport(String)
    case unauthorized(message: String?, code: String?)
    case sessionExpired
    case server(status: Int, message: String, code: String?)
    case decoding(String)
    case missingClient

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效，请检查是否写成 http://IP:5700"
        case .transport(let message):
            return "网络连接失败：\(message)"
        case .unauthorized(let message, let code):
            if code == "two_factor_required" { return "请输入两步验证码" }
            if code == "captcha_required" { return message ?? "需要完成人机验证" }
            return message ?? "登录已失效，请重新登录"
        case .sessionExpired:
            return "登录已失效，请重新登录"
        case .server(let status, let message, _):
            // 面板对 viewer 的写操作统一回 403 + {"error":"权限不足"}，直接展示会让人以为是 bug。
            if status == 403, message.isEmpty || message == "权限不足" {
                return "权限不足：当前账号没有执行该操作的权限（viewer 为只读角色）"
            }
            if status == 404, message.isEmpty {
                return "接口不存在，面板版本可能不匹配"
            }
            return message
        case .decoding(let detail):
            return "数据解析失败：\(detail)"
        case .missingClient:
            return "尚未连接面板"
        }
    }

    /// 面板侧的机器可读错误码，用于区分「要 2FA」「要验证码」「密码错」等情况。
    var code: String? {
        switch self {
        case .unauthorized(_, let code), .server(_, _, let code):
            return code
        default:
            return nil
        }
    }

    var message: String { errorDescription ?? "未知错误" }

    /// access token 过期、可以尝试刷新续期的情况。
    /// 登录相关的 401（密码错、要 2FA、要验证码、账号锁定）不属于「过期」，不能拿去刷新。
    var isAuthExpired: Bool {
        let loginCodes = [
            "invalid_credentials", "two_factor_required",
            "captcha_required", "invalid_totp", "account_locked"
        ]
        switch self {
        case .unauthorized(_, let code):
            if let code { return !loginCodes.contains(code) }
            return true
        case .sessionExpired:
            return true
        default:
            return false
        }
    }
}
