import Foundation

/// 面板任务。字段全部按「可能缺失」处理：面板不同版本会增减字段，
/// 少一个字段不该让整页崩掉。
struct PanelTask: Decodable, Identifiable, Equatable {
    let id: Int
    var name: String?
    var command: String?
    var cronExpression: String?
    /// 面板把多条定时规则以换行存进 `cron_expression`，同时单独给出解析后的数组。
    /// 编辑时必须按数组还原成多行，否则保存会把多余的规则冲掉。
    var cronExpressions: [String]?
    var taskType: String?
    var status: Double?
    var enabled: Bool?
    var isPinned: Bool?
    var timeout: Int?
    var maxRetries: Int?
    var retryInterval: Int?
    var notifyOnFailure: Bool?
    var notifyOnSuccess: Bool?
    var notifyOnAbort: Bool?
    var successExitCodes: String?
    var allowMultipleInstances: Bool?
    var lastRunAt: String?
    var lastRunStatus: Int?
    var lastRunningTime: Double?
    var lastSkipReason: String?
    var pid: Int?
    var sortOrder: Int?
    var listOrder: Int?
    var createdAt: String?
    var updatedAt: String?
    var taskBefore: String?
    var taskAfter: String?

    var displayName: String { (name?.isEmpty == false) ? name! : "任务 #\(id)" }

    var statusValue: Double { status ?? 1 }

    var runState: TaskRunState {
        switch statusValue {
        case 2: return .running
        case 0.5: return .queued
        case 0: return .disabled
        case 1: return .idle
        default: return .unknown
        }
    }

    var isEnabled: Bool {
        if let enabled { return enabled }
        return statusValue != 0
    }

    /// 拆成一条条规则：优先用面板给好的数组，退化为按换行切分。
    var cronLines: [String] {
        if let cronExpressions, !cronExpressions.isEmpty {
            return cronExpressions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let raw = cronExpression ?? ""
        return raw
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var hasMultipleCrons: Bool { cronLines.count > 1 }

    /// 列表里一行展示用：多条时用「 · 」连起来。
    var cronText: String {
        let lines = cronLines
        guard !lines.isEmpty else { return "未设置" }
        return lines.joined(separator: " · ")
    }

    /// 编辑器里的原始文本：一条一行，提交时原样发回面板。
    var cronEditorText: String {
        cronLines.joined(separator: "\n")
    }

    var isManualTask: Bool { (taskType ?? "cron") == "manual" }
}

enum TaskRunState {
    case running
    case queued
    case idle
    case disabled
    case unknown

    var text: String {
        switch self {
        case .running: return "运行中"
        case .queued: return "排队中"
        case .idle: return "空闲"
        case .disabled: return "已禁用"
        case .unknown: return "未知"
        }
    }
}

/// 新建 / 编辑任务的请求体，字段名与面板 `POST /tasks`、`PUT /tasks/:id` 对齐。
struct TaskDraft {
    var name: String = ""
    var command: String = ""
    var cronExpression: String = "0 0 * * *"
    var taskType: String = "cron"
    var timeout: Int = 0
    var maxRetries: Int = 0
    var retryInterval: Int = 0
    var notifyOnFailure: Bool = false
    var notifyOnSuccess: Bool = false
    var successExitCodes: String = "0"
    var allowMultipleInstances: Bool = false

    init() {}

    init(task: PanelTask) {
        name = task.name ?? ""
        command = task.command ?? ""
        // 用多行原样回填，保证「一个任务多条触发规则」编辑后不被压成一条。
        let existing = task.cronEditorText
        cronExpression = existing.isEmpty ? "0 0 * * *" : existing
        taskType = task.taskType ?? "cron"
        timeout = task.timeout ?? 0
        maxRetries = task.maxRetries ?? 0
        retryInterval = task.retryInterval ?? 0
        notifyOnFailure = task.notifyOnFailure ?? false
        notifyOnSuccess = task.notifyOnSuccess ?? false
        successExitCodes = task.successExitCodes ?? "0"
        allowMultipleInstances = task.allowMultipleInstances ?? false
    }

    /// 面板侧 `NormalizeExpressions` 的口径：按行拆分、去空白、丢掉空行、再用换行拼回去。
    var normalizedCron: String {
        cronExpression
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var cronLines: [String] {
        normalizedCron.isEmpty ? [] : normalizedCron.components(separatedBy: "\n")
    }

    var json: [String: Any] {
        [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "command": command.trimmingCharacters(in: .whitespacesAndNewlines),
            "cron_expression": normalizedCron,
            "task_type": taskType,
            "timeout": timeout,
            "max_retries": maxRetries,
            "retry_interval": retryInterval,
            "notify_on_failure": notifyOnFailure,
            "notify_on_success": notifyOnSuccess,
            "success_exit_codes": successExitCodes,
            "allow_multiple_instances": allowMultipleInstances
        ]
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "任务名称不能为空" }
        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "执行命令不能为空" }
        if taskType == "cron" && cronLines.isEmpty {
            return "定时任务需要填写 Cron 表达式"
        }
        return nil
    }
}

enum CronPreset: String, CaseIterable, Identifiable {
    case everyMinute = "每分钟"
    case every5 = "每 5 分钟"
    case every30 = "每 30 分钟"
    case hourly = "每小时"
    case daily = "每天 0 点"
    case daily8 = "每天 8 点"
    case weekly = "每周一 9 点"
    case monthly = "每月 1 号 0 点"

    var id: String { rawValue }

    var expression: String {
        switch self {
        case .everyMinute: return "* * * * *"
        case .every5: return "*/5 * * * *"
        case .every30: return "*/30 * * * *"
        case .hourly: return "0 * * * *"
        case .daily: return "0 0 * * *"
        case .daily8: return "0 8 * * *"
        case .weekly: return "0 9 * * 1"
        case .monthly: return "0 0 1 * *"
        }
    }
}
