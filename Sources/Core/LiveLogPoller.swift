import Foundation

/// `GET /tasks/:id/live-logs` 的返回：面板给的是「最后 200 行 + 是否跑完」快照，不是 SSE。
///
/// 注意 `status` 是**任务状态**（0 停用 / 0.5 排队 / 1 空闲 / 2 运行中），不是日志状态。
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
    /// 结束后的最终结论：0 成功 / 1 失败 / 3 终止，nil 表示未知。
    @Published private(set) var finalLogStatus: Int?

    private var pollingTask: Task<Void, Never>?
    private var lastSignature = ""

    /// 开始跟随某个任务的实时输出；任务跑完（done=true）自动停止并补一次完整日志。
    func start(client: APIClient, taskID: Int, interval: TimeInterval = 1.5) {
        stop()
        isDone = false
        errorMessage = nil
        finalLogStatus = nil
        isRunning = true
        lastSignature = ""

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let snapshot: LiveLogSnapshot = try await client.object("/tasks/\(taskID)/live-logs")

                    if snapshot.done == true {
                        // 任务一结束，面板就把内存里的增量缓冲清空，此时 `logs` 是空数组。
                        // 如果直接覆盖，屏幕上的日志会突然消失 —— 所以这里改用 latest-log 的完整内容兜底。
                        await self.finish(client: client, taskID: taskID, fallback: snapshot.logs)
                        self.isRunning = false
                        return
                    }

                    let incoming = snapshot.logs ?? []
                    let signature = "\(incoming.count)-\(incoming.last ?? "")"
                    if signature != self.lastSignature {
                        self.lines = Self.trim(incoming)
                        self.lastSignature = signature
                    }
                    self.lastUpdated = Date()
                } catch {
                    // 任务从「运行中」切到「已结束」的瞬间，面板可能先返回一次异常，继续轮询即可。
                    if let panel = error as? PanelError, panel.isAuthExpired {
                        self.errorMessage = panel.message
                        break
                    }
                    if self.isDone { break }
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

    /// 收尾：拿一次完整日志填满屏幕，顺带拿到真实的执行结论。
    private func finish(client: APIClient, taskID: Int, fallback: [String]?) async {
        if let log: TaskLog = try? await client.object("/tasks/\(taskID)/latest-log") {
            let text = (log.content ?? "").trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                self.lines = Self.trim(text.components(separatedBy: "\n"))
                self.finalLogStatus = log.status
                self.lastUpdated = Date()
                self.isDone = true
                return
            }
            self.finalLogStatus = log.status
        }
        let kept = Self.trim(fallback ?? [])
        if !kept.isEmpty { self.lines = kept }
        self.lastUpdated = Date()
        self.isDone = true
    }

    /// 面板的日志数组末尾常带一个空串（未换行的最后一段），直接显示会多出一行空白。
    private static func trim(_ incoming: [String]) -> [String] {
        var result = incoming
        while let last = result.last, last.isEmpty {
            result.removeLast()
        }
        return result
    }
}
