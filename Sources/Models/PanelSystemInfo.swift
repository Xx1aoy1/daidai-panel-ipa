import Foundation

/// `GET /system/info`：面板所在主机的实时状态。
///
/// 面板把内存/磁盘都换算成字节（`memory_total` 等）同时也给了百分比（`memory_usage`），
/// 网络是累计字节数 + 瞬时速率（`net_rx_speed` / `net_tx_speed`，单位 byte/s，无流量时为 0）。
/// `uptime` 是人话字符串（例如「16时33分」），不是秒数。
struct PanelSystemInfo: Decodable {
    var hostname: String?
    var machineCode: String?
    var os: String?
    var arch: String?
    var deploymentType: String?
    var version: String?
    var uptime: String?
    var dataDir: String?
    var goVersion: String?

    var cpuUsage: Double?
    var numCpu: Int?
    var goroutines: Int?

    var memoryTotal: Double?
    var memoryUsed: Double?
    var memoryFree: Double?
    var memoryUsage: Double?

    var diskTotal: Double?
    var diskUsed: Double?
    var diskFree: Double?
    var diskUsage: Double?

    var netRxBytes: Double?
    var netTxBytes: Double?
    var netRxSpeed: Double?
    var netTxSpeed: Double?

    var deploymentText: String {
        switch deploymentType ?? "" {
        case "docker": return "Docker"
        case "binary": return "二进制"
        case "magisk": return "Magisk 模块"
        case "": return "未知"
        default: return deploymentType ?? "未知"
        }
    }

    /// 内存/磁盘用量条用：优先百分比字段，缺了就用字节算。
    var memoryFraction: Double { fraction(usage: memoryUsage, used: memoryUsed, total: memoryTotal) }
    var diskFraction: Double { fraction(usage: diskUsage, used: diskUsed, total: diskTotal) }
    var cpuFraction: Double { min(max((cpuUsage ?? 0) / 100, 0), 1) }

    private func fraction(usage: Double?, used: Double?, total: Double?) -> Double {
        if let usage, usage > 0 { return min(max(usage / 100, 0), 1) }
        guard let used, let total, total > 0 else { return 0 }
        return min(max(used / total, 0), 1)
    }
}

/// `GET /system/health-check`：**没有 data 外壳**，直接是 `{items:[...], last_checked_at}`。
struct HealthCheckResult: Decodable {
    var items: [HealthItem]
    var lastCheckedAt: String?

    var allOK: Bool { items.allSatisfy { $0.isOK } }
}

struct HealthItem: Decodable, Identifiable {
    var name: String
    var status: String
    var message: String?

    var id: String { name }

    var isOK: Bool { (status).lowercased() == "ok" }

    var displayName: String {
        switch name {
        case "database": return "数据库"
        case "memory": return "内存"
        case "scheduler": return "调度器"
        case "network": return "网络"
        case "disk": return "磁盘"
        default: return name
        }
    }
}

/// `GET /logs/:id/raw-ticket`：签发一张 120 秒有效的一次性下载票据。
/// `url` 是相对路径（`/api/v1/logs/1574/raw?ticket=...`），拼上根地址即可直接下载，不需要再带 Authorization。
struct RawLogTicket: Decodable {
    var url: String
    var filename: String?
    var size: Double?
    var expiresAt: String?
    var expiresIn: Int?

    var expiresSeconds: Int { expiresIn ?? 120 }
}

/// `POST /scripts/format` 的返回（单层 `data`，不是双层）。
struct FormatResult: Decodable {
    var content: String?
    var formatter: String?
    var language: String?

    /// `formatter == "none"` 表示面板侧没装 black/shfmt/gofmt，内容原样返回。
    var didFormat: Bool {
        guard let formatter else { return false }
        return formatter != "none" && !formatter.isEmpty
    }

    var formatterText: String {
        guard didFormat else { return "面板没有可用的格式化器" }
        return "已用 \(formatter ?? "") 格式化"
    }
}

/// 只关心 `message` 的回执。
struct MessagePayload: Decodable {
    var message: String?
}
