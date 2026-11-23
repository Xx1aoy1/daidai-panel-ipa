import Foundation

/// 面板 `/scripts/run-code` 与 `/scripts/run`（inline）接受的语言名。
/// 取值来自面板的 `scriptLanguageExtMap`：python / javascript / node(mjs) / typescript / shell / go。
enum ScriptLanguage {
    static func detect(path: String) -> String? {
        var ext = (path as NSString).pathExtension.lowercased()
        if ext.isEmpty { return nil }
        if ext.hasPrefix(".") { ext.removeFirst() }
        switch ext {
        case "py": return "python"
        case "js", "cjs": return "javascript"
        case "mjs", "node": return "node"
        case "ts": return "typescript"
        case "sh", "bash": return "shell"
        case "go": return "go"
        default: return nil
        }
    }

    static func canRun(path: String) -> Bool {
        detect(path: path) != nil
    }

    /// 面板 `POST /scripts/format` 只认 python / shell / go / json 四种，
    /// JavaScript / TypeScript 传过去会被回 400「不支持的语言」，所以这里先挡一层。
    static func formatterLanguage(path: String) -> String? {
        if path.lowercased().hasSuffix(".json") { return "json" }
        switch detect(path: path) {
        case "python": return "python"
        case "shell": return "shell"
        case "go": return "go"
        default: return nil
        }
    }

    static func displayName(for language: String) -> String {
        switch language {
        case "python": return "Python"
        case "javascript": return "JavaScript"
        case "node": return "Node"
        case "typescript": return "TypeScript"
        case "shell": return "Shell"
        case "go": return "Go"
        default: return language
        }
    }
}
