import Foundation

/// `GET /system/dashboard?range=7` 返回的 `data`。
struct PanelDashboard: Decodable {
    var taskCount: Int?
    var enabledTasks: Int?
    var runningTasks: Int?
    var todayLogs: Int?
    var successLogs: Int?
    var failedLogs: Int?
    var abortedLogs: Int?
    var envCount: Int?
    var subCount: Int?
    var prevTaskCount: Int?
    var yesterdayLogs: Int?
    var yesterdaySuccess: Int?
    var yesterdayFailed: Int?
    var yesterdayAborted: Int?
    var recentLogs: [TaskLog]?
    var dailyStats: [DailyStat]?
    var rangeDays: Int?

    static let empty = PanelDashboard()

    var successRate: Double {
        let total = Double(todayLogs ?? 0)
        guard total > 0 else { return 0 }
        return Double(successLogs ?? 0) / total
    }

    var successRateText: String {
        guard (todayLogs ?? 0) > 0 else { return "—" }
        return String(format: "%.0f%%", successRate * 100)
    }

    var failedRate: Double {
        let total = Double(todayLogs ?? 0)
        guard total > 0 else { return 0 }
        return Double(failedLogs ?? 0) / total
    }

    var maxDailyTotal: Int {
        let values = (dailyStats ?? []).map { ($0.success ?? 0) + ($0.failed ?? 0) + ($0.aborted ?? 0) }
        return max(values.max() ?? 0, 1)
    }
}

struct DailyStat: Decodable, Identifiable {
    var date: String?
    var success: Int?
    var failed: Int?
    var aborted: Int?

    var id: String { date ?? UUID().uuidString }

    var total: Int { (success ?? 0) + (failed ?? 0) + (aborted ?? 0) }

    var shortDate: String {
        guard let date, date.count >= 10 else { return date ?? "" }
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])/\(parts[2])"
    }
}
