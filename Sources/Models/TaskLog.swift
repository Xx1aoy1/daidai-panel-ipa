import Foundation

/// 任务执行日志。`status`：0 成功 / 1 失败 / 2 运行中 / 3 手动终止。
struct TaskLog: Decodable, Identifiable, Equatable {
    let id: Int
    var taskId: Int?
    var content: String?
    var status: Int?
    var duration: Double?
    var logPath: String?
    var startedAt: String?
    var endedAt: String?
    var createdAt: String?
    var taskName: String?
    var task: TaskBrief?

    var statusKind: LogStatusKind { LogStatusKind(rawValue: status ?? -1) ?? .unknown }

    var titleText: String {
        if let taskName, !taskName.isEmpty { return taskName }
        if let task, let name = task.name, !name.isEmpty { return name }
        if let taskId { return "任务 #\(taskId)" }
        return "日志 #\(id)"
    }

    var startedDate: Date? { DateParser.parse(startedAt ?? createdAt) }

    var durationText: String {
        guard let duration, duration > 0 else { return "—" }
        if duration < 60 { return String(format: "%.1f 秒", duration) }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes) 分 \(seconds) 秒"
    }

    var contentLines: [String] {
        (content ?? "").components(separatedBy: "\n")
    }
}

struct TaskBrief: Decodable, Equatable {
    let id: Int?
    let name: String?
}

enum LogStatusKind: Int {
    case success = 0
    case failed = 1
    case running = 2
    case aborted = 3
    case unknown = -1

    var text: String {
        switch self {
        case .success: return "成功"
        case .failed: return "失败"
        case .running: return "运行中"
        case .aborted: return "已终止"
        case .unknown: return "未知"
        }
    }
}
