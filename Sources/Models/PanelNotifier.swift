import Foundation

/// 通知渠道（`GET /notifications` 的 `data` 元素）。
///
/// 面板把渠道配置整体塞进 `config` 这个 **JSON 字符串** 字段里，而不是嵌套对象，
/// 所以这里保持 String 原样，读取时再解析成字典。面板侧约束：config 里的值必须全是字符串，
/// 数字/布尔混进去会导致该渠道所有推送（含测试按钮）失败，所以写回时统一转成字符串。
struct NotifyChannel: Decodable, Identifiable, Equatable {
    let id: Int
    var name: String
    var type: String
    var config: String?
    var enabled: Bool
    var pushScope: String?
    var todaySendCount: Int?
    var lastTestAt: String?
    var lastTestStatus: String?
    var createdAt: String?
    var updatedAt: String?

    /// 绑定推送（bound）只发该任务绑定的渠道；默认推送（default）参与全局广播。
    var isBound: Bool { (pushScope ?? "default") == "bound" }

    var scopeText: String { isBound ? "绑定推送" : "默认推送" }

    var testStatusText: String? {
        switch lastTestStatus ?? "" {
        case "success": return "上次测试成功"
        case "failed": return "上次测试失败"
        default: return nil
        }
    }

    /// 把 `config` 解析成键值字典。面板保证值全是字符串，这里对历史脏数据（布尔/数字）做一次兼容转换。
    var configFields: [String: String] {
        guard let config,
              let data = config.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case let text as String:
                result[key] = text
            case let flag as Bool:
                result[key] = flag ? "true" : "false"
            case let number as NSNumber:
                result[key] = number.stringValue
            default:
                break
            }
        }
        return result
    }

    /// 列表里的一行摘要：只挑非密钥字段，避免把 token 直接摆到列表上。
    func summary(using type: NotifyChannelType?) -> String {
        let values = configFields
        var parts: [String] = []
        // 挑几个「一眼能认出是哪个渠道」的字段，密钥类一律跳过。
        let preferred = ["url", "webhook", "smtp_host", "chat_id", "topic", "smtp_user", "to", "server"]
        for key in preferred {
            guard let value = values[key], !value.isEmpty else { continue }
            if key == "webhook" || key == "url" {
                parts.append(Self.shortHost(value))
            } else {
                parts.append(value)
            }
            if parts.count >= 2 { break }
        }
        return parts.isEmpty ? scopeText : parts.joined(separator: " · ")
    }

    /// 把 URL 压成「主机 + 末段」，列表里不至于占满一行。
    private static func shortHost(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host else {
            return raw.count > 32 ? String(raw.prefix(32)) + "…" : raw
        }
        return host
    }
}

/// 渠道类型注册表（`GET /notifications/types`）。面板内置 19 种，字段定义带 widget 类型，
/// 客户端据此动态生成表单，新增渠道类型不用改客户端。
struct NotifyChannelType: Decodable, Identifiable {
    var type: String
    var name: String
    var icon: String?
    var fields: [NotifyField]

    var id: String { type }

    /// 卡片上用的 SF Symbol。面板的 icon 名是自家前端图标集，跟 SF Symbols 对不上，这里按类型映射。
    var systemImage: String {
        switch type {
        case "webhook", "custom": return "antenna.radiowaves.left.and.right"
        case "email": return "envelope.fill"
        case "telegram": return "paperplane.fill"
        case "dingtalk": return "bubble.left.and.bubble.right.fill"
        case "wecom", "wecom_app": return "building.2.fill"
        case "bark": return "bell.badge.fill"
        case "pushplus", "serverchan", "pushdeer", "pushme", "pushover", "wxpusher": return "arrow.up.forward.app.fill"
        case "feishu": return "bird.fill"
        case "gotify", "ntfy", "chanify", "igot": return "dot.radiowaves.left.and.right"
        case "qmsg": return "message.fill"
        case "discord": return "gamecontroller.fill"
        case "slack": return "number"
        default: return "bell.fill"
        }
    }

    var iconTint: String { type }
}

/// 动态表单里的一个字段。
struct NotifyField: Decodable, Identifiable {
    var key: String
    var label: String?
    var widget: String?
    var placeholder: String?
    var required: Bool?
    var options: [NotifyOption]?

    /// 同类型里 key 可能重复（企业微信的 `content_template` 就出现了两次），
    /// 所以 Identifiable 用 key + label 组合，避免 ForEach 撞 id。
    var id: String { "\(key)#\(label ?? "")" }

    /// 是否为密钥字段：password widget，或者键名看起来就是凭据。
    var isSecret: Bool {
        if (widget ?? "") == "password" { return true }
        return ["token", "secret", "smtp_pass", "key", "app_token"].contains(key)
    }

    var kind: NotifyFieldKind {
        switch widget ?? "input" {
        case "password": return .password
        case "select": return .select
        case "textarea": return .textarea
        default: return .input
        }
    }

    var title: String { label ?? key }
}

enum NotifyFieldKind {
    case input
    case password
    case select
    case textarea
}

struct NotifyOption: Decodable, Identifiable, Equatable {
    var value: String
    var label: String
    var id: String { value }
}

/// 新建/编辑渠道时提交的数据。
struct NotifyDraft {
    var name: String
    var type: String
    var fields: [String: String]
    var pushScope: String

    /// `config` 必须是 JSON **字符串**，且值全是字符串。
    var configJSON: String {
        let cleaned = fields.filter { !$0.value.isEmpty }
        guard let data = try? JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    var createJSON: [String: Any] {
        ["name": name, "type": type, "config": configJSON, "push_scope": pushScope]
    }

    /// PUT 是按键更新：不带的字段不动已有值，所以编辑时四件套都传。
    var updateJSON: [String: Any] {
        ["name": name, "type": type, "config": configJSON, "push_scope": pushScope]
    }

    static func from(channel: NotifyChannel) -> NotifyDraft {
        NotifyDraft(name: channel.name,
                    type: channel.type,
                    fields: channel.configFields,
                    pushScope: channel.pushScope ?? "default")
    }
}
