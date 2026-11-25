import Foundation

// 「后台进程」页的接口。只对**管理员本人**开放（面板挂了 RequireUserToken + RequireAdmin），
// 应用令牌 / 脚本令牌调不通；所以客户端入口只在 admin 账号下显示。
extension APIClient {

    /// `GET /system/processes?scope=task|all`
    /// - `task`：只列带任务标识（`DAIDAI_TASK_ID`）的进程，含已经脱离任务的子孙进程；
    /// - `all`：连面板自身的 nginx、sh 等系统进程一起列，Magisk 模块版不开放。
    func fetchProcesses(scope: ProcessScope) async throws -> ProcessListPayload {
        let data = try await send(path: "/system/processes",
                                  query: ["scope": scope.rawValue])
        return try Self.decodeObject(data)
    }

    /// `POST /system/processes/kill {pid, start_ticks}`
    /// - `start_ticks` 必须回传列表里拿到的原值：PID 被系统复用时面板会用这个值挡住，回 409「进程已退出」。
    /// - 面板自身、PID 1、与面板同进程组的进程一律 400 拒绝。
    func killProcess(pid: Int, startTicks: UInt64) async throws -> KillProcessResult {
        let data = try await send(path: "/system/processes/kill",
                                  method: "POST",
                                  json: ["pid": pid, "start_ticks": startTicks])
        return try Self.decodeObject(data)
    }
}

enum ProcessScope: String, CaseIterable, Identifiable {
    case task
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: return "任务进程"
        case .all: return "全部进程"
        }
    }
}

struct KillProcessResult: Decodable {
    var message: String?
    /// 信号发出后进程是否真的退出了；false 时面板会提示「稍后刷新查看」。
    var exited: Bool?
}
