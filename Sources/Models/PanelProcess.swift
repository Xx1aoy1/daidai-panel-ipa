import Foundation

/// 「后台进程」页（`GET /system/processes`）里的一条进程。
///
/// 面板把任务拉起的常驻进程和普通系统进程都塞进同一个结构，
/// `task_id == nil` 表示不是任务拉起的（只会在 `scope=all` 里出现）。
struct PanelProcess: Decodable, Identifiable {
    let pid: Int
    var pgid: Int?
    var taskId: Int?
    var taskName: String?
    var cmdline: String?
    var startedAt: String?
    var rssBytes: Int64?
    /// `running_with_task` / `detached` / `other`，见面板 `ProcessState*` 常量。
    var state: String?
    /// `/proc/<pid>/stat` 的原始 starttime，结束进程时要原样带回去，防止 PID 复用后误杀。
    var startTicks: UInt64?

    /// `pid` 在面板里唯一，但「全部进程」里同一 pid 只会出现一次，直接当 id 用。
    var id: Int { pid }

    var displayCommand: String {
        let text = (cmdline ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "（无命令行）" : text
    }

    var stateText: String {
        switch (state ?? "").lowercased() {
        case "running_with_task": return "任务运行中"
        case "detached": return "已脱离任务"
        case "other": return "非任务进程"
        case "": return "未知"
        default: return state ?? "未知"
        }
    }

    var stateTintName: String {
        switch (state ?? "").lowercased() {
        case "running_with_task": return "success"
        case "detached": return "warning"
        default: return "idle"
        }
    }

    var taskText: String? {
        guard let taskId else { return nil }
        let name = (taskName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "已删除的任务 #\(taskId)" : "\(name)（#\(taskId)）"
    }

    var rssText: String {
        guard let rssBytes, rssBytes > 0 else { return "—" }
        let mb = Double(rssBytes) / 1024 / 1024
        if mb < 1 { return String(format: "%.0f KB", Double(rssBytes) / 1024) }
        return String(format: "%.1f MB", mb)
    }

    /// 面板给的是「进程启动时刻」，配合当前时间就是已运行时长。
    var runtimeText: String {
        guard let startedAt, let date = DateParser.parse(startedAt) else { return "—" }
        let seconds = Date().timeIntervalSince(date)
        guard seconds >= 0 else { return "—" }
        if seconds < 60 { return "\(Int(seconds)) 秒" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟" }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        let days = Int(seconds / 86400)
        return "\(days) 天"
    }

    var startedText: String {
        guard let startedAt, let date = DateParser.parse(startedAt) else { return "—" }
        return DateText.absolute(date)
    }
}

/// `GET /system/processes` 的返回：`{data:[...], supported, all_supported, scope}`。
struct ProcessListPayload: Decodable {
    var data: [PanelProcess]?
    /// 面板所在系统能不能读 `/proc`（Windows 开发机上是 false）。
    var supported: Bool?
    /// 「显示全部进程」是否可用；Magisk 模块版不开放。
    var allSupported: Bool?
    var scope: String?

    var items: [PanelProcess] { data ?? [] }
}
