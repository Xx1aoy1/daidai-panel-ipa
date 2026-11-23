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
