import Foundation

/// 在线运行脚本：先 `POST /scripts/run`（或 `/scripts/run-code`）拿 run_id，
/// 再按固定间隔轮询 `/scripts/run/:run_id/logs`，跑完自动停。
/// 与任务日志不同，这里的 `logs` 在结束后**不会**被清空，所以可以原地保留输出。
@MainActor
final class ScriptRunner: ObservableObject {

    enum Source {
        /// 运行脚本目录里已保存的文件。
        case saved(path: String)
        /// 运行编辑框里的当前内容（不覆盖已保存的文件，用于改完先试跑）。
        case inline(path: String, content: String)
        /// 运行一段临时代码。
        case code(_ text: String, language: String)
    }

    @Published private(set) var lines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isDone = false
    @Published private(set) var isSuccess = false
    @Published private(set) var statusText = "准备就绪"
    @Published private(set) var exitCode: Int?
    @Published private(set) var errorMessage: String?
    @Published private(set) var runID: String?
    @Published private(set) var startedAt: Date?

    private var pollingTask: Task<Void, Never>?

    var elapsedText: String {
        guard let startedAt else { return "" }
        let interval = Date().timeIntervalSince(startedAt)
        if interval < 60 { return String(format: "%.1f 秒", interval) }
        return "\(Int(interval) / 60) 分 \(Int(interval) % 60) 秒"
    }

    func start(client: APIClient, source: Source, interval: TimeInterval = 0.8) {
        stopPolling()
        lines = []
        isDone = false
        isSuccess = false
        exitCode = nil
        errorMessage = nil
        isRunning = true
        statusText = "正在启动…"
        startedAt = Date()

        pollingTask = Task { [weak self] in
            guard let self else { return }
            let id: String
            do {
                switch source {
                case .saved(let path):
                    id = try await client.runSavedScript(path: path)
                case .inline(let path, let content):
                    id = try await client.runSavedScript(path: path, content: content)
                case .code(let text, let language):
                    id = try await client.runCode(text, language: language)
                }
            } catch {
                self.errorMessage = (error as? PanelError)?.message ?? error.localizedDescription
                self.isRunning = false
                self.statusText = "启动失败"
                return
            }

            if id.isEmpty {
                self.errorMessage = "面板没有返回 run_id（可能不允许在线运行）"
                self.isRunning = false
                self.statusText = "启动失败"
                return
            }

            self.runID = id
            self.statusText = "运行中"

            while !Task.isCancelled {
                do {
                    let snapshot: DebugRunSnapshot = try await client.debugLogs(runID: id)
                    self.lines = Self.trim(snapshot.logs ?? [])
                    self.exitCode = snapshot.exitCode
                    self.statusText = snapshot.statusText
                    if snapshot.done == true {
                        self.isDone = true
                        self.isSuccess = snapshot.isSuccess
                        self.statusText = snapshot.statusText
                        break
                    }
                } catch {
                    self.errorMessage = (error as? PanelError)?.message ?? error.localizedDescription
                    break
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
            }
            self.isRunning = false
        }
    }

    /// 请求面板停掉这次运行（不影响已产生的输出）。
    func requestStop(client: APIClient) {
        guard let runID else { return }
        Task {
            do {
                try await client.stopDebugRun(runID: runID)
                self.statusText = "正在终止…"
            } catch {
                self.errorMessage = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
    }

    /// 清掉面板侧的临时运行记录并释放本地状态。
    func cleanup(client: APIClient) {
        guard let runID else { return }
        Task { try? await client.clearDebugRun(runID: runID) }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
    }

    private static func trim(_ incoming: [String]) -> [String] {
        var result = incoming
        while let last = result.last, last.isEmpty {
            result.removeLast()
        }
        return result
    }
}
