import SwiftUI
import UIKit

struct LogDetailView: View {
    @EnvironmentObject private var session: SessionStore

    let logID: Int
    let title: String

    @State private var log: TaskLog?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var copiedHint = false
    @State private var isDownloading = false
    @State private var shareFile: ShareFile?

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    LoadingHint(text: "读取日志…")
                    Spacer()
                }
            } else if let errorText {
                VStack(spacing: 12) {
                    ErrorBanner(text: errorText)
                    Button("重试") { Task { await load() } }
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16)
            } else if let log {
                content(log)
            } else {
                EmptyStateView(icon: "doc.text", title: "日志不存在")
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    if let log, let taskId = log.taskId, log.statusKind == .running {
                        NavigationLink(destination: LiveLogView(taskID: taskId, title: title)) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                    }
                    Button {
                        copyContent()
                    } label: {
                        Image(systemName: copiedHint ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        Task { await downloadRaw() }
                    } label: {
                        if isDownloading {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                    .disabled(isDownloading || isLoading)
                }
            }
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ log: TaskLog) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusBadge(text: log.statusKind.text, color: color(log.statusKind))
                    Text("耗时 \(log.durationText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if let started = DateParser.parse(log.startedAt ?? log.createdAt) {
                        Text(DateText.total(started))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("#\(log.id)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                let body = log.content ?? ""
                if body.isEmpty {
                    Text("（日志内容为空）")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text(body)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func color(_ kind: LogStatusKind) -> Color {
        switch kind {
        case .success: return AppTheme.success
        case .failed: return AppTheme.failure
        case .running: return AppTheme.running
        case .aborted: return AppTheme.warning
        case .unknown: return AppTheme.idle
        }
    }

    private func load() async {
        guard let client = session.client else {
            isLoading = false
            errorText = "尚未连接面板"
            return
        }
        isLoading = true
        errorText = nil
        do {
            log = try await client.fetchLog(id: logID)
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func copyContent() {
        guard let content = log?.content, !content.isEmpty else { return }
        UIPasteboard.general.string = content
        copiedHint = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedHint = false
        }
    }

    /// 面板的原始日志文件落在磁盘上，直连下载不能带 Authorization，
    /// 所以先换一张 120 秒的一次性票据，再按票据里的 url 下载。
    private func downloadRaw() async {
        guard let client = session.client else { return }
        isDownloading = true
        errorText = nil
        do {
            let url = try await client.downloadRawLog(id: logID)
            shareFile = ShareFile(url: url)
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isDownloading = false
    }
}
