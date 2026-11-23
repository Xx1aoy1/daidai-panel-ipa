import SwiftUI

enum LogFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case success = "成功"
    case failed = "失败"
    case running = "运行中"

    var id: String { rawValue }

    /// 面板 `GET /logs?status=`：0 成功 / 1 失败 / 2 运行中 / 3 手动终止。
    var statusValue: Int? {
        switch self {
        case .all: return nil
        case .success: return 0
        case .failed: return 1
        case .running: return 2
        }
    }
}

@MainActor
final class LogListViewModel: ObservableObject {
    @Published var logs: [TaskLog] = []
    @Published var keyword = ""
    @Published var filter: LogFilter = .all
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorText: String?
    @Published var toast: String?
    @Published var total = 0

    private var page = 1
    private var hasMore = false

    func reload(client: APIClient) async {
        if logs.isEmpty { isLoading = true }
        errorText = nil
        do {
            let result = try await client.fetchLogs(status: filter.statusValue,
                                                    keyword: keyword,
                                                    page: 1,
                                                    pageSize: 30)
            logs = result.items
            total = result.total
            page = 1
            hasMore = result.hasMore
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadMore(client: APIClient) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        do {
            let next = page + 1
            let result = try await client.fetchLogs(status: filter.statusValue,
                                                    keyword: keyword,
                                                    page: next,
                                                    pageSize: 30)
            page = next
            total = result.total
            hasMore = result.hasMore
            let existing = Set(logs.map { $0.id })
            logs.append(contentsOf: result.items.filter { !existing.contains($0.id) })
        } catch {
            hasMore = false
        }
        isLoadingMore = false
    }

    /// 单条删除（`DELETE /logs/:id`）。面板会同时删记录和磁盘上的日志文件。
    func delete(_ log: TaskLog, client: APIClient) async {
        do {
            try await client.deleteLog(id: log.id)
            logs.removeAll { $0.id == log.id }
            total = max(total - 1, 0)
            flash("已删除 1 条日志")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    /// 清理 N 天前的日志（`DELETE /logs/clean?days=N`），记录与文件一起删。
    func clean(days: Int, client: APIClient) async {
        do {
            let message = try await client.cleanLogs(days: days)
            flash(message ?? "已清理 \(days) 天前的日志")
            await reload(client: client)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct LogListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = LogListViewModel()
    @State private var showCleanDialog = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("筛选", selection: $model.filter) {
                    ForEach(LogFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .onChange(of: model.filter) { _ in
                    Task { await reload() }
                }

                content
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("执行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if session.canWrite {
                            Button {
                                showCleanDialog = true
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        Button {
                            Task { await reload() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.isLoading)
                    }
                }
            }
            .searchable(text: $model.keyword, prompt: "按任务名搜索日志")
            .onSubmit(of: .search) {
                Task { await reload() }
            }
        }
        .navigationViewStyle(.stack)
        .task { await reload() }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.bottom, 28)
            }
        }
        .confirmationDialog("清理会同时删除日志记录和磁盘上的日志文件，删掉就找不回来了。",
                            isPresented: $showCleanDialog,
                            titleVisibility: .visible) {
            Button("清理 7 天前") { Task { await clean(days: 7) } }
            Button("清理 30 天前") { Task { await clean(days: 30) } }
            Button("清理 90 天前") { Task { await clean(days: 90) } }
            Button("取消", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorText = model.errorText, model.logs.isEmpty {
            VStack(spacing: 12) {
                ErrorBanner(text: errorText)
                Button("重试") { Task { await reload() } }
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(16)
            Spacer()
        } else if model.isLoading && model.logs.isEmpty {
            LoadingHint(text: "正在加载日志…")
            Spacer()
        } else if model.logs.isEmpty {
            EmptyStateView(icon: "doc.text",
                           title: "还没有执行日志",
                           message: "任务跑起来之后这里就会出现记录")
            Spacer()
        } else {
            List {
                ForEach(model.logs) { log in
                    NavigationLink(destination: LogDetailView(logID: log.id, title: log.titleText)) {
                        LogRow(log: log)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if session.canWrite {
                            Button(role: .destructive) {
                                Task { await deleteLog(log) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .onAppear {
                        if log.id == model.logs.last?.id {
                            Task { await loadMore() }
                        }
                    }
                }

                if model.isLoadingMore {
                    LoadingHint(text: "加载更多…")
                } else {
                    Text("共 \(model.total) 条日志")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        do {
            let client = try session.requireClient()
            await model.reload(client: client)
        } catch {
            model.errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let client = session.client else { return }
        await model.loadMore(client: client)
    }

    private func deleteLog(_ log: TaskLog) async {
        guard let client = session.client else { return }
        await model.delete(log, client: client)
    }

    private func clean(days: Int) async {
        guard let client = session.client else { return }
        await model.clean(days: days, client: client)
    }
}

struct LogRow: View {
    let log: TaskLog

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.titleText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(DateText.relative(log.startedAt ?? log.createdAt))
                    Text("·")
                    Text(log.durationText)
                    if let taskId = log.taskId {
                        Text("·")
                        Text("#\(taskId)")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            StatusBadge(text: log.statusKind.text, color: color, compact: true)
        }
        .padding(.vertical, 3)
    }

    private var color: Color {
        switch log.statusKind {
        case .success: return AppTheme.success
        case .failed: return AppTheme.failure
        case .running: return AppTheme.running
        case .aborted: return AppTheme.warning
        case .unknown: return AppTheme.idle
        }
    }
}
