import SwiftUI

@MainActor
final class LoginLogListViewModel: ObservableObject {
    @Published var logs: [LoginLogEntry] = []
    @Published var keyword = ""
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
            let result = try await client.fetchLoginLogs(page: 1, pageSize: 30, username: keyword)
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
            let result = try await client.fetchLoginLogs(page: next, pageSize: 30, username: keyword)
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

    /// `DELETE /security/login-logs` 是清空全部，没有「只清 N 天前」的口子。
    func clearAll(client: APIClient) async {
        do {
            let message = try await client.clearLoginLogs()
            flash(message ?? "登录日志已清空")
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

/// 登录日志：面板只支持「用户名精确筛选」+ 分页，没有按时间/状态过滤的入参。
struct LoginLogListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = LoginLogListViewModel()
    @State private var showClearConfirm = false
    @State private var filterText = ""

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if !filterText.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(AppTheme.accent)
                        Text("只看用户「\(filterText)」")
                            .font(.system(size: 12))
                        Spacer()
                        Button("清除") {
                            filterText = ""
                            model.keyword = ""
                            Task { await reload() }
                        }
                        .font(.system(size: 12))
                    }
                }
            }

            if model.isLoading && model.logs.isEmpty {
                Section { LoadingHint(text: "读取登录日志…") }
            } else if model.logs.isEmpty {
                Section {
                    EmptyStateView(icon: "person.badge.key",
                                   title: filterText.isEmpty ? "还没有登录记录" : "这个用户没有登录记录",
                                   message: filterText.isEmpty
                                   ? "登录成功、失败、IP 被拦截都会记一条"
                                   : "用户名是精确匹配，确认没打错字")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(model.logs) { log in
                        LoginLogRow(log: log)
                            .onAppear {
                                if log.id == model.logs.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                    }
                    if model.isLoadingMore {
                        LoadingHint(text: "加载更多…")
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("共 \(model.total) 条")
                } footer: {
                    Text("面板只提供「用户名精确筛选」和分页，没有时间范围或状态过滤；想按时间看就往回翻，想瘦身就直接清空。")
                        .font(.system(size: 11))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("登录日志")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filterText, prompt: "按用户名精确筛选")
        .onSubmit(of: .search) {
            model.keyword = filterText
            Task { await reload() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.logs.isEmpty)
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .refreshable { await reload() }
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
                    .padding(.bottom, 26)
            }
        }
        .confirmationDialog("会删掉全部登录日志（面板没有按时间清理的接口），删完不可恢复。",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("清空全部登录日志", role: .destructive) {
                Task { await clear() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.reload(client: client)
    }

    private func loadMore() async {
        guard let client = session.client else { return }
        await model.loadMore(client: client)
    }

    private func clear() async {
        guard let client = session.client else { return }
        await model.clearAll(client: client)
    }
}

private struct LoginLogRow: View {
    let log: LoginLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: log.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 13))
                .foregroundColor(log.isSuccess ? AppTheme.success : AppTheme.failure)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.usernameText)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(log.methodText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Text(log.ipText)
                        .font(.system(size: 11, design: .monospaced))
                    Text("·")
                    Text(log.clientText)
                        .lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)

                Text(log.messageText)
                    .font(.system(size: 10))
                    .foregroundColor(log.isSuccess ? .secondary : AppTheme.failure)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Text(log.timeText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
