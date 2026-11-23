import SwiftUI

@MainActor
final class UserListViewModel: ObservableObject {
    @Published var users: [PanelAccount] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toast: String?

    func load(client: APIClient) async {
        if users.isEmpty { isLoading = true }
        errorText = nil
        do {
            let loaded = try await client.fetchUsers()
            users = loaded.sorted { lhs, rhs in
                if lhs.roleValue != rhs.roleValue {
                    let order: [PanelRole] = [.admin, .ops, .viewer]
                    let left = order.firstIndex(of: lhs.roleValue) ?? 9
                    let right = order.firstIndex(of: rhs.roleValue) ?? 9
                    if left != right { return left < right }
                }
                return lhs.id < rhs.id
            }
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct UserListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = UserListViewModel()

    @State private var showCreate = false

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if model.isLoading && model.users.isEmpty {
                LoadingHint(text: "读取账号列表…")
                    .listRowBackground(Color.clear)
            } else if model.users.isEmpty {
                EmptyStateView(icon: "person.2.slash",
                               title: "没有读到账号",
                               message: "正常情况下至少有当前登录的账号，试试下拉刷新")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.users) { account in
                        NavigationLink {
                            UserDetailView(account: account) {
                                Task { await reload() }
                            }
                            .environmentObject(session)
                        } label: {
                            UserRow(account: account, isMe: account.id == session.user?.id)
                        }
                    }
                } header: {
                    Text("共 \(model.users.count) 个账号")
                } footer: {
                    Text("面板会在改角色、禁用、重置密码、删除时**立即撤销该用户的全部会话**，对方手上的令牌会立刻失效。")
                        .font(.system(size: 11))
                }
            }

            Section {
                Button {
                    showCreate = true
                } label: {
                    Label("新建账号", systemImage: "person.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                }
            } footer: {
                Text("三个角色：管理员（全部权限）、运维（可改任务与脚本，管理类接口 403）、只读（只能看任务与日志）。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("用户管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
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
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationView {
                UserCreateView { message in
                    model.flash(message)
                    Task { await reload() }
                }
                .environmentObject(session)
            }
            .navigationViewStyle(.stack)
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }
}

private struct UserRow: View {
    let account: PanelAccount
    let isMe: Bool

    var body: some View {
        HStack(spacing: 11) {
            Text(account.initial)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(account.roleValue == .admin ? AppTheme.accent : AppTheme.idle)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.username)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if isMe {
                        StatusBadge(text: "我", color: AppTheme.accent, compact: true)
                    }
                    if !account.isEnabled {
                        StatusBadge(text: "已禁用", color: AppTheme.failure, compact: true)
                    }
                    if account.twoFactorEnabled == true {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.success)
                    }
                }
                HStack(spacing: 6) {
                    Text(account.roleValue.title)
                    Text("·")
                    Text(account.lastLoginText)
                    if account.twoFactorEnabled == true {
                        Text("· 已开 2FA")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }
}
