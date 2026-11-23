import SwiftUI

/// 跟随任务实时输出。面板 `/tasks/:id/live-logs` 给的是「最后 200 行 + done」快照，
/// 所以这里用 1.5 秒轮询，任务跑完自动停。
struct LiveLogView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var poller = LiveLogPoller()

    let taskID: Int
    let title: String

    @State private var follow = true

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if poller.lines.isEmpty {
                            EmptyStateView(icon: "text.alignleft",
                                           title: poller.isRunning ? "等待输出…" : "暂无输出",
                                           message: poller.isRunning ? "任务容器还没写入内容" : nil)
                        } else {
                            ForEach(Array(poller.lines.enumerated()), id: \.offset) { index, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: poller.lines.count) { _ in
                    guard follow else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    follow.toggle()
                } label: {
                    Image(systemName: follow ? "arrow.down.to.line.compact" : "pause.circle")
                }
            }
        }
        .onAppear { start() }
        .onDisappear { poller.stop() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(poller.isDone ? doneColor : (poller.isRunning ? AppTheme.success : AppTheme.warning))
                .frame(width: 7, height: 7)

            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if let last = poller.lastUpdated {
                Text("· 更新于 \(DateText.absolute(last))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let errorMessage = poller.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.failure)
                    .lineLimit(1)
            } else {
                Text("\(poller.lines.count) 行")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if poller.isDone || !poller.isRunning {
                Button {
                    start()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.pageBackground)
    }

    private func start() {
        guard let client = session.client else { return }
        poller.start(client: client, taskID: taskID)
    }

    /// 结束后用 latest-log 的 status 给出真实结论（0 成功 / 1 失败 / 3 终止）。
    private var statusText: String {
        if poller.isRunning { return "跟随中" }
        if poller.isDone {
            switch poller.finalLogStatus {
            case 0: return "执行成功"
            case 1: return "执行失败"
            case 3: return "已终止"
            case 2: return "运行中"
            default: return "已结束"
            }
        }
        return "已停止"
    }

    private var doneColor: Color {
        switch poller.finalLogStatus {
        case 0: return AppTheme.success
        case 1: return AppTheme.failure
        case 3: return AppTheme.warning
        default: return AppTheme.idle
        }
    }
}
