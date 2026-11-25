import SwiftUI

/// 订阅拉取进度：直接把面板的 SSE 输出铺在屏幕上，可随时中止。
struct SubscriptionPullView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SubscriptionPullModel()

    let subscription: PanelSubscription
    @State private var follow = true
    @State private var stopError: String?

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if model.lines.isEmpty {
                            EmptyStateView(icon: model.isStreaming ? "arrow.triangle.2.circlepath" : "text.alignleft",
                                           title: model.isStreaming ? "等待输出…" : "没有输出",
                                           message: model.isStreaming ? "面板正在 clone / checkout，通常几秒内出第一行" : nil)
                        } else {
                            ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .onChange(of: model.lines.count) { _ in
                    guard follow else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            if let stopError {
                ErrorBanner(text: stopError)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(subscription.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if model.isStreaming {
                    Button {
                        stopPull()
                    } label: {
                        Image(systemName: "stop.circle")
                            .foregroundColor(AppTheme.failure)
                    }
                    .disabled(model.isStopping)
                } else {
                    Button {
                        start()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                Button {
                    follow.toggle()
                } label: {
                    Image(systemName: follow ? "arrow.down.to.line.compact" : "pause.circle")
                }
            }
        }
        .onAppear { start() }
        .onDisappear { model.stop() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(model.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(model.lines.count) 行")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.pageBackground)
    }

    private var statusColor: Color {
        if model.isStreaming { return AppTheme.running }
        if model.errorText != nil { return AppTheme.failure }
        switch model.doneReason ?? "" {
        case "finished": return model.failed ? AppTheme.failure : AppTheme.success
        case "reconnect", "timeout", "closed": return AppTheme.warning
        default: return AppTheme.idle
        }
    }

    private func color(for line: String) -> Color {
        if line.contains("[错误]") || line.contains("fatal:") { return AppTheme.failure }
        if line.contains("[完成]") { return line.contains("失败") ? AppTheme.failure : AppTheme.success }
        if line.contains("[开始拉取]") || line.contains("[git ") { return AppTheme.accent }
        return .primary
    }

    private func start() {
        guard let client = session.client else { return }
        stopError = nil
        model.start(client: client, subscriptionID: subscription.id)
    }

    private func stopPull() {
        guard let client = session.client else { return }
        model.isStopping = true
        stopError = nil
        Task {
            do {
                try await client.stopSubscriptionPull(id: subscription.id)
            } catch {
                stopError = (error as? PanelError)?.message ?? error.localizedDescription
            }
            model.isStopping = false
        }
    }
}
