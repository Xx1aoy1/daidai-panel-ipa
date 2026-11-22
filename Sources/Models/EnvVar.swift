import Foundation

struct EnvVar: Decodable, Identifiable, Equatable {
    let id: Int
    var name: String?
    var value: String?
    var remarks: String?
    var enabled: Bool?
    var group: String?
    var important: Bool?
    var position: Double?
    var createdAt: String?

    var displayName: String { name ?? "未命名变量" }
    var isEnabled: Bool { enabled ?? true }
    var isMasked: Bool { (value ?? "").contains("******") || (value ?? "").contains("••••") }

    /// 名称像凭据的变量默认折叠显示，避免在公共场合暴露。
    var looksSensitive: Bool {
        let upper = (name ?? "").uppercased()
        let keys = ["TOKEN", "COOKIE", "PASSWORD", "SECRET", "KEY", "AUTH", "SIGN", "SESSION"]
        return keys.contains { upper.contains($0) }
    }
}

struct EnvDraft {
    var name: String = ""
    var value: String = ""
    var remarks: String = ""
    var group: String = ""
    var enabled: Bool = true

    init() {}

    init(env: EnvVar) {
        name = env.name ?? ""
        value = env.isMasked ? "" : (env.value ?? "")
        remarks = env.remarks ?? ""
        group = env.group ?? ""
        enabled = env.enabled ?? true
    }

    var json: [String: Any] {
        [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "value": value,
            "remarks": remarks,
            "group": group,
            "enabled": enabled
        ]
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "变量名不能为空" }
        if value.isEmpty { return "变量值不能为空（面板不支持空值变量）" }
        return nil
    }
}
