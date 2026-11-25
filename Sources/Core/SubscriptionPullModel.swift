import Foundation

/// 订阅拉取的实时输出。
///
/// 面板 `GET /subscriptions/:id/pull-stream` 是标准 SSE：每行输出一条 `data:`，
/// 结束时 `event: done` + `data: finished|not_running|reconnect|timeout|closed`。
/// 网页端把 `finished/not_running/closed` 当结束，`reconnect` 当「面板被重启/连接断了，重连一次」。
///
/// 注意顺序：**必须先 `PUT /pull` 再连流**。面板只在拉取启动时才注册 broadcaster，
/// 反过来先连流会立刻收到 `not_running`；而拉取结束（哪怕是失败）后 broadcaster 会被移除，
/// 所以也不能靠「事后重连」补输出 —— 只能靠 broadcaster 里的 history 重放。
@MainActor
final class SubscriptionPullModel: ObservableObject {
    @Published var lines: [String] = []
    @Published var isStreaming = false
    @Published var isFinished = false
    /// `finished` / `not_running` / `reconnect` / `timeout` / `closed`。
    @Published var doneReason: String?
    @Published var errorText: String?
    @Published var isStopping = false

    private var streamTask: Task<Void, Never>?
    private var retried = false

    var failed: Bool {
        if doneReason == "reconnect" || doneReason == "timeout" || doneReason == "closed" { return true }
        if errorText != nil { return true }
        return lines.contains { $0.contains("[错误]") || $0.contains("[完成] 耗时") && $0.contains("失败") }
    }

    var statusText: String {
        if isStreaming { return "拉取中" }
        if let errorText { return errorText }
        switch doneReason ?? "" {
        case "finished": return failed ? "拉取失败" : "拉取完成"
        case "not_running": return "没有进行中的拉取"
        case "reconnect": return "连接中断（面板可能重启了）"
        case "timeout": return "等待超时（5 分钟无输出）"
        case "closed": return "流已关闭"
        case "": return "准备中"
        default: return doneReason ?? ""
        }
    }

    func start(client: APIClient, subscriptionID: Int) {
        streamTask?.cancel()
        lines = []
        isStreaming = false
        isFinished = false
        doneReason = nil
        errorText = nil
        retried = false

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.run(client: client, subscriptionID: subscriptionID)
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func run(client: APIClient, subscriptionID: Int) async {
        // 先在面板上把任务拉起来，再连流，这样 broadcaster 已经存在。
        do {
            try await client.pullSubscription(id: subscriptionID)
        } catch {
            // 400「该订阅正在拉取中」是正常情况（定时任务刚好在跑），继续连流即可；
            // 其他错误（403/404/网络）直接展示，但仍然尝试连一次流，好让用户看到面板侧进度。
            let message = (error as? PanelError)?.message ?? error.localizedDescription
            if !message.contains("正在拉取") {
                errorText = message
            }
        }

        await consume(client: client, subscriptionID: subscriptionID)
    }

    private func consume(client: APIClient, subscriptionID: Int) async {
        isStreaming = true
        defer { isStreaming = false }

        do {
            let request = try client.subscriptionPullStreamRequest(id: subscriptionID)
            let bytes = try await client.streamBytes(request)

            var event = "message"
            var hadOutput = false

            for try await raw in bytes.lines {
                if Task.isCancelled { return }
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw

                if line.hasPrefix("event:") {
                    event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                    continue
                }
                guard line.hasPrefix("data:") else { continue }

                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

                if event == "done" {
                    isFinished = true
                    doneReason = payload
                    // 连上就被判 not_running：可能是拉取已经秒结束（失败很快）或者我们在 pull 之后连晚了。
                    // 给一次重试机会，但只重试一次，避免面板异常时空转。
                    if payload == "not_running", !hadOutput, !retried {
                        retried = true
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        await run(client: client, subscriptionID: subscriptionID)
                    }
                    return
                }

                hadOutput = true
                lines.append(payload)
            }

            // 流正常关掉但没收到 done：面板重启或被反代截断。
            isFinished = true
            if doneReason == nil { doneReason = "closed" }
        } catch {
            if Task.isCancelled { return }
            isStreaming = false
            isFinished = true
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }
}
