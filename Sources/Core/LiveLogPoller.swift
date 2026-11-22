import Foundation

/// `GET /tasks/:id/live-logs` 的返回：面板直接给「最后 200 行 + 是否跑完」的快照，
/// 不是 SSE，所以客户端按固定间隔轮询即可，跑完就停。
struct LiveLogSnapshot: Decodable {
    var logs: [String]?
    var done: Bool?
    var status: Double?
}

@MainActor
final class LiveLogPoller: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isDone = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private var pollingTask: Task<Void, Never>?
    private var lastSignature = ""

    /// 开始跟随某个任务的实时输出；任务跑完（done=true）会自动停止。
    func start(client: APIClient, taskID: Int, interval: TimeInterval = 1.5) {
        stop()
        isDone = false
        errorMessage = nil
        isRunning = true
        lastSignature = ""

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let snapshot: LiveLogSnapshot = try await client.object("/tasks/\(taskID)/live-logs")
                    let incoming = snapshot.logs ?? []
                    let signature = "\(incoming.count)-\(incoming.last ?? "")"
                    if signature != self.lastSignature {
                        self.lines = incoming
                        self.lastSignature = signature
                    }
                    self.lastUpdated = Date()
                    if snapshot.done == true {
                        self.isDone = true
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

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
    }
}
