import Foundation

struct PanelSubscription: Decodable, Identifiable, Equatable {
    let id: Int
    var alias: String?
    var name: String?
    var type: String?
    var url: String?
    var branch: String?
    var schedule: String?
    var enabled: Bool?
    var status: Int?
    /// 面板字段名是 `last_pull_at`，旧版本这里误写成 `last_run_at`，导致同步时间永远不显示。
    var lastPullAt: String?
    var saveDir: String?
    var hasAuthToken: Bool?
    var autoAddTask: Bool?
    var subPath: String?

    var displayName: String {
        if let alias, !alias.isEmpty { return alias }
        if let name, !name.isEmpty { return name }
        if let url, !url.isEmpty { return url }
        return "订阅 #\(id)"
    }

    var isEnabled: Bool { enabled ?? true }

    /// 面板的 `type` 取值是 `git-repo` / `file` / `url`，不是 `git`。
    var typeText: String {
        switch (type ?? "").lowercased() {
        case "git-repo", "git": return "Git"
        case "file": return "本地文件"
        case "url": return "URL"
        case "": return "Git"
        default: return type ?? "Git"
        }
    }

    var scheduleText: String {
        let value = (schedule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未设置" : value
    }

    var pullText: String {
        guard let lastPullAt, !lastPullAt.isEmpty else { return "从未拉取" }
        return DateText.relative(lastPullAt)
    }
}

/// 脚本目录树节点。
///
/// 面板 `/scripts/tree` 返回的是 antd Tree 结构，真实字段是
/// `key`（完整相对路径）、`title`（文件名）、`type`（directory/file）、
/// `isLeaf`、`extension`、`size`、`mtime` —— 没有 `name` 和 `path`。
/// 早期版本按 `name`/`path` 解码，结果每个节点都显示成「未命名」且打不开。
struct ScriptNode: Decodable, Identifiable {
    var key: String?
    var title: String?
    var type: String?
    var isLeaf: Bool?
    var size: Int?
    var mtime: Int?
    var fileExtension: String?
    var children: [ScriptNode]?

    private enum CodingKeys: String, CodingKey {
        case key, title, type, isLeaf, size, mtime, children
        case fileExtension = "extension"
    }

    /// 完整相对路径，作为请求 `/scripts/content?path=` 的参数。
    var path: String { key ?? title ?? "" }

    var id: String { path }

    var isDirectory: Bool {
        if let type, !type.isEmpty { return type == "directory" }
        return isLeaf == false
    }

    var displayName: String {
        if let title, !title.isEmpty { return title }
        let name = (key as NSString?)?.lastPathComponent ?? ""
        return name.isEmpty ? "未命名" : name
    }

    var iconName: String {
        if isDirectory { return "folder" }
        var ext = (fileExtension ?? "").lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        if ext.isEmpty { ext = (displayName as NSString).pathExtension.lowercased() }
        switch ext {
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "js", "mjs", "cjs", "ts": return "curlybraces"
        case "sh", "bash": return "terminal"
        case "json", "yaml", "yml", "toml", "ini", "conf", "env": return "slider.horizontal.3"
        case "md", "txt", "log": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        default: return "doc"
        }
    }

    /// 只有这些扩展名面板才允许在 App 内当文本打开。
    var isEditable: Bool {
        var ext = (fileExtension ?? "").lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        if ext.isEmpty { ext = (displayName as NSString).pathExtension.lowercased() }
        let textExts: Set<String> = ["py", "js", "mjs", "cjs", "ts", "sh", "bash",
                                     "json", "yaml", "yml", "toml", "ini", "conf",
                                     "env", "md", "txt", "log", "csv", "go", "sql", "xml"]
        return textExts.contains(ext)
    }

    var sizeText: String {
        guard let size, size > 0 else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }

    var modifiedText: String {
        guard let mtime, mtime > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(mtime))
        return DateText.relative(date)
    }
}

struct ScriptContent: Decodable {
    var path: String?
    var content: String?
    var binary: Bool?
    var size: Int?
}

// MARK: - 在线运行

/// `GET /scripts/run/:run_id/logs` 的返回。注意是包在 `data` 里的。
struct DebugRunSnapshot: Decodable {
    var logs: [String]?
    var done: Bool?
    var exitCode: Int?
    var status: String?

    var statusText: String {
        switch (status ?? "").lowercased() {
        case "running": return "运行中"
        case "success", "succeeded": return "执行成功"
        case "failed", "error": return "执行失败"
        case "stopped", "killed", "aborted": return "已终止"
        default: return done == true ? "已结束" : "运行中"
        }
    }

    /// `status` 是字符串，成败要看它而不是退出码（被终止时退出码可能为 nil）。
    var isSuccess: Bool {
        let value = (status ?? "").lowercased()
        if value == "success" || value == "succeeded" { return true }
        if let exitCode { return exitCode == 0 }
        return false
    }
}

/// 脚本版本历史（`GET /scripts/versions?path=`）。
struct ScriptVersion: Decodable, Identifiable {
    let id: Int
    var scriptPath: String?
    var version: Int?
    var message: String?
    var contentLength: Int?
    var createdAt: String?

    var versionText: String { "v\(version ?? 0)" }
}

/// 单个版本的完整内容（`GET /scripts/versions/:id`），只用于预览，不提供回滚。
struct ScriptVersionDetail: Decodable {
    var id: Int?
    var version: Int?
    var message: String?
    var content: String?
    var createdAt: String?

    var versionText: String { "v\(version ?? 0)" }
}

