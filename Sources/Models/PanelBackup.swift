import Foundation

/// `GET /system/backups` 里的一条备份记录。
///
/// 面板直接读 backups 目录的文件来生成，所以只有三个字段：
/// `name`（文件名）、`size`（字节）、`created_at`（文件 mtime）。
/// 目录为空时接口回的是 `{"data":null}`，解析侧要按空数组兜。
struct PanelBackup: Decodable, Identifiable, Equatable {
    let name: String
    let size: Int64?
    let createdAt: String?

    var id: String { name }

    var lowerName: String { name.lowercased() }

    /// `.enc` 是加了密码的，恢复时必须提供同一个密码；其余两种是明文。
    var isEncrypted: Bool { lowerName.hasSuffix(".enc") }

    var isLegacyJSON: Bool { lowerName.hasSuffix(".json") }

    var kindText: String {
        if isEncrypted { return "加密" }
        if isLegacyJSON { return "旧版 JSON" }
        if lowerName.hasSuffix(".tar.gz") || lowerName.hasSuffix(".tgz") { return "压缩包" }
        return "备份"
    }

    var kindIcon: String {
        if isEncrypted { return "lock.doc.fill" }
        if isLegacyJSON { return "doc.text.fill" }
        return "archivebox.fill"
    }

    var sizeText: String { Bytes.text(Double(size ?? 0)) }

    var timeText: String {
        guard let date = DateParser.parse(createdAt) else { return createdAt ?? "—" }
        return "\(DateText.relative(date))（\(DateText.total(date))）"
    }

    var shortTimeText: String {
        guard let date = DateParser.parse(createdAt) else { return "—" }
        return DateText.absolute(date)
    }

    /// 面板只接受这四种扩展名，列表里混进别的东西说明目录被人手动塞了文件。
    var isRestorable: Bool {
        lowerName.hasSuffix(".json")
            || lowerName.hasSuffix(".enc")
            || lowerName.hasSuffix(".tgz")
            || lowerName.hasSuffix(".tar.gz")
    }
}

/// 备份范围。面板 8 个开关，全不选时服务端会退回「全选默认」，所以客户端宁可显式传。
struct BackupSelection: Equatable {
    var configs = true
    var tasks = true
    var subscriptions = true
    var envVars = true
    var logs = true
    var scripts = true
    var dependencies = true
    var taskViews = true

    static let all = BackupSelection()

    /// 全不选。面板对「全不选」会退回默认全选，所以提交前要先在客户端挡住。
    static var empty: BackupSelection {
        BackupSelection(configs: false,
                        tasks: false,
                        subscriptions: false,
                        envVars: false,
                        logs: false,
                        scripts: false,
                        dependencies: false,
                        taskViews: false)
    }

    var isEmpty: Bool {
        !configs && !tasks && !subscriptions && !envVars
            && !logs && !scripts && !dependencies && !taskViews
    }

    var selectedCount: Int {
        BackupItem.allCases.filter { self[$0] }.count
    }

    var summaryText: String {
        let picked = BackupItem.allCases.filter { self[$0] }.map(\.shortTitle)
        if picked.isEmpty { return "未选择" }
        if picked.count == BackupItem.allCases.count { return "全部 \(picked.count) 项" }
        return picked.joined(separator: " · ")
    }

    subscript(item: BackupItem) -> Bool {
        get {
            switch item {
            case .configs: return configs
            case .tasks: return tasks
            case .subscriptions: return subscriptions
            case .envVars: return envVars
            case .logs: return logs
            case .scripts: return scripts
            case .dependencies: return dependencies
            case .taskViews: return taskViews
            }
        }
        set {
            switch item {
            case .configs: configs = newValue
            case .tasks: tasks = newValue
            case .subscriptions: subscriptions = newValue
            case .envVars: envVars = newValue
            case .logs: logs = newValue
            case .scripts: scripts = newValue
            case .dependencies: dependencies = newValue
            case .taskViews: taskViews = newValue
            }
        }
    }

    /// 面板要的是 snake_case，env_vars / task_views 两个键别写错。
    var jsonObject: [String: Bool] {
        [
            "configs": configs,
            "tasks": tasks,
            "subscriptions": subscriptions,
            "env_vars": envVars,
            "logs": logs,
            "scripts": scripts,
            "dependencies": dependencies,
            "task_views": taskViews
        ]
    }
}

extension BackupSelection: Decodable {
    private enum CodingKeys: String, CodingKey {
        case configs
        case tasks
        case subscriptions
        case envVars = "env_vars"
        case logs
        case scripts
        case dependencies
        case taskViews = "task_views"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configs = (try? container.decode(Bool.self, forKey: .configs)) ?? false
        tasks = (try? container.decode(Bool.self, forKey: .tasks)) ?? false
        subscriptions = (try? container.decode(Bool.self, forKey: .subscriptions)) ?? false
        envVars = (try? container.decode(Bool.self, forKey: .envVars)) ?? false
        logs = (try? container.decode(Bool.self, forKey: .logs)) ?? false
        scripts = (try? container.decode(Bool.self, forKey: .scripts)) ?? false
        dependencies = (try? container.decode(Bool.self, forKey: .dependencies)) ?? false
        taskViews = (try? container.decode(Bool.self, forKey: .taskViews)) ?? false
    }
}

/// 备份可选的 8 类数据，和面板 `BackupSelection` 的字段一一对应。
enum BackupItem: String, CaseIterable, Identifiable {
    case configs
    case tasks
    case subscriptions
    case envVars
    case logs
    case scripts
    case dependencies
    case taskViews

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configs: return "系统配置"
        case .tasks: return "定时任务"
        case .subscriptions: return "订阅仓库"
        case .envVars: return "环境变量"
        case .logs: return "执行日志"
        case .scripts: return "脚本文件"
        case .dependencies: return "依赖列表"
        case .taskViews: return "任务视图"
        }
    }

    var shortTitle: String {
        switch self {
        case .configs: return "配置"
        case .tasks: return "任务"
        case .subscriptions: return "订阅"
        case .envVars: return "变量"
        case .logs: return "日志"
        case .scripts: return "脚本"
        case .dependencies: return "依赖"
        case .taskViews: return "视图"
        }
    }

    var detail: String {
        switch self {
        case .configs: return "面板设置、通知渠道、用户账号"
        case .tasks: return "任务定义与定时规则"
        case .subscriptions: return "Git 订阅与上次拉取状态"
        case .envVars: return "全部变量（含密钥，注意保管）"
        case .logs: return "执行历史与按天统计"
        case .scripts: return "脚本目录里的文件内容"
        case .dependencies: return "已装包清单（恢复后按需重装）"
        case .taskViews: return "任务分组视图"
        }
    }

    var icon: String {
        switch self {
        case .configs: return "slider.horizontal.3"
        case .tasks: return "clock.badge.checkmark"
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .envVars: return "key.fill"
        case .logs: return "doc.text.fill"
        case .scripts: return "curlybraces"
        case .dependencies: return "shippingbox.fill"
        case .taskViews: return "square.grid.2x2.fill"
        }
    }
}

/// `GET /system/restore/progress` 的返回。
///
/// 空闲时是 `{active:false, status:"idle", percent:0, updated_at:"0001-01-01T00:00:00Z"}`，
/// 恢复中是 `running` + stage/message/percent，结束后 `completed` / `failed`。
struct RestoreProgress: Decodable, Equatable {
    var active: Bool?
    var status: String?
    var filename: String?
    var source: String?
    var stage: String?
    var message: String?
    var percent: Int?
    var error: String?
    var startedAt: String?
    var updatedAt: String?
    var selection: BackupSelection?

    var isRunning: Bool { status == "running" || active == true }
    var isCompleted: Bool { status == "completed" }
    var isFailed: Bool { status == "failed" }
    var isIdle: Bool { status == "idle" || status == nil }

    var percentValue: Double {
        Double(min(max(percent ?? 0, 0), 100))
    }

    var stageText: String {
        if let message, !message.isEmpty { return message }
        switch stage ?? "" {
        case "reading": return "正在读取备份文件…"
        case "decrypting": return "正在解密…"
        case "extracting": return "正在解包并校验…"
        case "analyzing": return "正在分析备份内容…"
        case "restoring-data": return "正在写入数据库…"
        case "restoring-scripts": return "正在还原脚本…"
        case "finishing": return "正在收尾…"
        default: return isRunning ? "正在恢复…" : (status ?? "—")
        }
    }

    var sourceText: String? {
        switch source ?? "" {
        case "daidai": return "呆呆面板备份"
        case "qinglong": return "青龙备份（自动转换）"
        case "": return nil
        default: return source
        }
    }
}

/// `POST /system/backup` 的回执：`{message, data:{path}}`，path 在服务端是绝对路径。
struct BackupCreateResult: Decodable {
    var message: String?
    var data: BackupCreatedPath?

    struct BackupCreatedPath: Decodable {
        var path: String?
    }

    /// 服务端给的是 `/app/Dumb-Panel/backups/xxx.tgz`，只取文件名用来定位列表项。
    var filename: String? {
        guard let path = data?.path, !path.isEmpty else { return nil }
        return path.split(separator: "/").last.map(String.init)
    }
}
