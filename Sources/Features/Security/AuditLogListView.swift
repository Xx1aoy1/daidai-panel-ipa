import SwiftUI

@MainActor
final class AuditLogListViewModel: ObservableObject {
    @Published var logs: [SecurityAuditEntry] = []
    @Published var action: SecurityAuditAction?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorText: String?
    @Published var total = 0

    private var page = 1
    private var hasMore = false

    func reload(client: APIClient) async {
        if logs.isEmpty { isLoading = true }
        errorText = nil
        do {
            let result = try await client.fetchAuditLogs(page: 1, pageSize: 30, action: action)
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
            let result = try await client.fetchAuditLogs(page: next, pageSize: 30, action: action)
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
}

/// 安全审计：面板只记录**成功**的敏感操作，筛选也只支持「操作类型精确匹配」。
///
/// 这一页最有用的是事后对账：谁在什么时候改了配置 / 删了备份 / 清了日志 / 踢了人。
struct AuditLogListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = AuditLogListViewModel()

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if let action = model.action {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(AppTheme.accent)
                        Text("只看「\(action.label)」")
                            .font(.system(size: 12))
                        Spacer()
                        Button("清除") {
                            model.action = nil
                            Task { await reload() }
                        }
                        .font(.system(size: 12))
                    }
                }
            }

            if model.isLoading && model.logs.isEmpty {
                Section { LoadingHint(text: "读取审计日志…") }
            } else if model.logs.isEmpty {
                Section {
                    EmptyStateView(icon: "checklist.checked",
                                   title: model.action == nil ? "还没有审计记录" : "这类操作还没有记录",
                                   message: model.action == nil
                                   ? "改动密码、用户、备份、配置、白名单这类敏感操作成功后才会记一条"
                                   : "换一个操作类型，或清除筛选看全部")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(model.logs) { entry in
                        AuditLogRow(entry: entry)
                            .onAppear {
                                if entry.id == model.logs.last?.id {
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
                    Text("只记成功的操作；「详情」是面板写的人话描述，命令类操作会截到前 200 字。")
                        .font(.system(size: 11))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("审计日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Menu {
                        Picker("操作类型", selection: Binding(get: { model.action },
                                                          set: { newValue in
                                                              model.action = newValue
                                                              Task { await reload() }
                                                          })) {
                            Text("全部操作").tag(Optional<SecurityAuditAction>.none)
                            ForEach(SecurityAuditAction.allCases) { action in
                                Text(action.label).tag(SecurityAuditAction?.some(action))
                            }
                        }
                    } label: {
                        Image(systemName: model.action == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
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
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.reload(client: client)
    }

    private func loadMore() async {
        guard let client = session.client else { return }
        await model.loadMore(client: client)
    }
}

private struct AuditLogRow: View {
    let entry: SecurityAuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.actionLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
                Spacer(minLength: 4)
                Text(entry.timeText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Text(entry.actorText)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Text(entry.detailText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)

            HStack(spacing: 4) {
                Image(systemName: "network")
                    .font(.system(size: 9))
                Text(entry.ipText)
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    /// 销毁/覆盖数据的标红，改系统状态的标黄，其余用主色。
    private var tint: Color {
        switch entry.risk {
        case .danger: return AppTheme.failure
        case .warning: return AppTheme.warning
        case .normal: return AppTheme.accent
        }
    }
}
