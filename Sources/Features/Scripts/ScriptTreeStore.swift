import Foundation

/// 脚本目录树的单一数据源。
///
/// 面板 `/scripts/tree` 一次性返回整棵树，所以子目录不需要再发请求；
/// 但也意味着**任何一次改名/移动/删除都要重新拉整棵树**，否则父目录里还留着旧节点。
/// 之前每个子目录各自持有一份 children，改动后父级列表不刷新，看起来像「文件凭空消失」。
@MainActor
final class ScriptTreeStore: ObservableObject {
    @Published var root: [ScriptNode] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var lastLoadedAt: Date?

    var isLoaded: Bool { lastLoadedAt != nil }

    func load(client: APIClient) async {
        if root.isEmpty { isLoading = true }
        errorText = nil
        do {
            root = try await client.fetchScriptTree()
            lastLoadedAt = Date()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    /// 按相对路径取某一层的子节点；`nil` 或空串表示根目录。
    func nodes(at path: String?) -> [ScriptNode] {
        guard let path, !path.isEmpty else { return root }
        guard let node = find(path: path) else { return [] }
        return node.children ?? []
    }

    func find(path: String) -> ScriptNode? {
        func search(_ nodes: [ScriptNode]) -> ScriptNode? {
            for node in nodes {
                if node.path == path { return node }
                if let children = node.children, let hit = search(children) { return hit }
            }
            return nil
        }
        return search(root)
    }

    /// 目录选择器用：根目录 + 所有子目录，带层级缩进。
    /// 用结构体而不是元组：`ForEach(id: \.path)` 对元组 keypath 支持不稳。
    func directoryOptions() -> [ScriptDirectoryOption] {
        var result: [ScriptDirectoryOption] = [
            ScriptDirectoryOption(path: "", title: "脚本根目录", depth: 0)
        ]
        func walk(_ nodes: [ScriptNode], depth: Int) {
            for node in nodes where node.isDirectory {
                result.append(ScriptDirectoryOption(path: node.path, title: node.displayName, depth: depth))
                if let children = node.children {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(root, depth: 1)
        return result
    }

    /// 当前目录下的路径拼接（面板只认 `/` 分隔的相对路径）。
    func join(dir: String?, name: String) -> String {
        guard let dir, !dir.isEmpty else { return name }
        return dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }
}

struct ScriptDirectoryOption: Identifiable {
    let path: String
    let title: String
    let depth: Int

    var id: String { path }
}

enum ScriptPath {
    /// `a/b/c.py` → `a/b`；根目录下的文件返回空串。
    static func dir(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard let slash = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[normalized.startIndex..<slash])
    }

    static func leaf(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard let slash = normalized.lastIndex(of: "/") else { return normalized }
        return String(normalized[normalized.index(after: slash)...])
    }

    /// 面板 `validateScriptLeafName` 的本地预检：空、带分隔符、`.`/`..`、`<>:"|?*` 和控制字符都不行。
    static func validate(name raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "名称不能为空" }
        if name.contains("/") || name.contains("\\") { return "名称不能包含路径分隔符" }
        if name == "." || name == ".." { return "名称不能为 . 或 .." }
        let invalid = CharacterSet(charactersIn: "<>:\"|?*")
        if name.rangeOfCharacter(from: invalid) != nil { return "名称包含非法字符（< > : \" | ? *）" }
        if name.rangeOfCharacter(from: .controlCharacters) != nil { return "名称包含控制字符" }
        if name == ".git" { return "名称不可用：.git" }
        return nil
    }

    /// 面板 `allowedExtensions` 白名单，上传前先挡一层，省得大文件传完才报错。
    static func isAllowedUpload(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext.isEmpty { return true }   // 面板对无扩展名放行
        let allowed: Set<String> = [
            "py", "js", "mjs", "sh", "ts", "json", "yaml", "yml", "txt", "md",
            "conf", "ini", "env", "toml", "xml", "csv", "png", "jpg", "jpeg",
            "gif", "svg", "ico", "bmp", "webp", "log", "htm", "html", "css",
            "sql", "bat", "cmd", "ps1", "go", "so"
        ]
        return allowed.contains(ext)
    }
}
