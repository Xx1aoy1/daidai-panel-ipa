import Foundation

struct PanelSubscription: Decodable, Identifiable, Equatable {
    let id: Int
    var name: String?
    var type: String?
    var url: String?
    var branch: String?
    var schedule: String?
    var enabled: Bool?
    var status: Int?
    var lastRunAt: String?
    var remarks: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let url, !url.isEmpty { return url }
        return "订阅 #\(id)"
    }

    var isEnabled: Bool { enabled ?? true }

    var typeText: String {
        switch (type ?? "").lowercased() {
        case "git", "": return "Git"
        case "file": return "本地文件"
        case "url": return "URL"
        default: return type ?? "Git"
        }
    }

    var scheduleText: String {
        let value = (schedule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未设置" : value
    }
}

/// 脚本目录树节点：`type` 为 "directory" 或 "file"。
struct ScriptNode: Decodable, Identifiable {
    var name: String?
    var path: String?
    var type: String?
    var size: Int?
    var children: [ScriptNode]?

    var id: String { path ?? name ?? UUID().uuidString }

    var isDirectory: Bool { (type ?? "") == "directory" }

    var displayName: String { name ?? path ?? "未命名" }

    var iconName: String {
        if isDirectory { return "folder" }
        let ext = (name as NSString?)?.pathExtension.lowercased() ?? ""
        switch ext {
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "mjs", "ts": return "curlybraces"
        case "sh": return "terminal"
        case "json", "yaml", "yml", "toml", "ini", "conf", "env": return "slider.horizontal.3"
        case "md", "txt", "log": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        default: return "doc"
        }
    }

    var sizeText: String {
        guard let size, size > 0 else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }
}

struct ScriptContent: Decodable {
    var path: String?
    var content: String?
    var binary: Bool?
    var size: Int?
}
