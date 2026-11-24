import SwiftUI

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var sessions: [PanelSession] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toast: String?

    /// 当前会话排最前，其余按创建时间倒序（面板本身就是倒序返回的）。
    func load(client: APIClient) async {
        if sessions.isEmpty { isLoading = true }
        errorText = nil
        do {
            let loaded = try await client.fetchSessions()
            sessions = loaded.sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                let left = DateParser.parse(lhs.createdAt) ?? .distantPast
                let right = DateParser.parse(rhs.createdAt) ?? .distantPast
                return left > right
            }
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func revoke(_ target: PanelSession, client: APIClient) async -> Bool {
        do {
            let message = try await client.revokeSession(id: target.id)
            sessions.removeAll { $0.id == target.id }
            flash(message ?? "会话已撤销")
            return true
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            return false
        }
    }

    func revokeOthers(client: APIClient) async -> Bool {
        do {
            let message = try await client.revokeOtherSessions()
            flash(message ?? "已撤销所有其他会话")
            await load(client: client)
            return true
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            return false
        }
    }

    func revokeAll(of target: PanelSession, client: APIClient) async -> Bool {
        guard let userID = target.userId else { return false }
        do {
            let message = try await client.revokeAllSessions(userID: userID)
            flash(message ?? "已撤销该账号的全部会话")
            await load(client: client)
            return true
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            return false
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

/// 活动会话：admin 能看到所有人的会话（网页端 + APP 端），可以单个撤销或整账号踢下线。
struct SessionListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SessionListViewModel()

    @State private var pendingAction: PendingAction?

    /// iOS 15 同一个视图挂多个 `.confirmationDialog` 只有最后一个稳定生效，收成一个状态机。
    private enum PendingAction: Identifiable {
        case revoke(PanelSession)
        case kickUser(PanelSession)
        case revokeOthers

        var id: String {
            switch self {
            case .revoke(let item): return "revoke-\(item.id)"
            case .kickUser(let item): return "kick-\(item.id)"
            case .revokeOthers: return "others"
            }
        }
    }

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if model.isLoading && model.sessions.isEmpty {
                Section { LoadingHint(text: "读取会话列表…") }
            } else if model.sessions.isEmpty {
                Section {
                    EmptyStateView(icon: "rectangle.stack.person.crop",
                                   title: "没有有效会话",
                                   message: "下拉刷新再看一眼")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(model.sessions) { item in
                        SessionRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingAction = .revoke(item)
                                } label: {
                                    Label("撤销", systemImage: "xmark.circle")
                                }
                                if let userID = item.userId, userID > 0 {
                                    Button {
                                        pendingAction = .kickUser(item)
                                    } label: {
                                        Label("踢该账号", systemImage: "person.crop.circle.badge.xmark")
                                    }
                                    .tint(AppTheme.warning)
                                }
                            }
                    }
                } header: {
                    Text("共 \(model.sessions.count) 个")
                } footer: {
                    Text("这里的「APP 端 / 网页端」是按请求头判定的：客户端带 `X-Client-Type: app` 就记为 APP 会话，走 APP 端的会话数上限，不会顶掉网页登录。")
                        .font(.system(size: 11))
                }
            }

            Section {
                Button(role: .destructive) {
                    pendingAction = .revokeOthers
                } label: {
                    Label("撤销我的其他会话", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                }
            } footer: {
                Text("只踢掉**你自己账号**除当前设备以外的会话，不影响列表里别人的登录。当前设备会保留。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("活动会话")
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
                    .padding(.bottom, 26)
            }
        }
        .confirmationDialog(dialogTitle, isPresented: dialogBinding, titleVisibility: .visible) {
            if case let .revoke(target)? = pendingAction {
                Button("撤销会话", role: .destructive) {
                    pendingAction = nil
                    Task { await revoke(target) }
                }
            }
            if case let .kickUser(target)? = pendingAction {
                Button("全部踢下线", role: .destructive) {
                    pendingAction = nil
                    Task { await kickAll(of: target) }
                }
            }
            if case .revokeOthers? = pendingAction {
                Button("撤销其他会话", role: .destructive) {
                    pendingAction = nil
                    Task { await revokeOthers() }
                }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        }
    }

    private var dialogBinding: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }

    private var dialogTitle: String {
        switch pendingAction {
        case .revoke(let target)?:
            if target.isCurrent {
                return "这是当前设备的会话，撤销后你自己会立刻退出登录。"
            }
            return "撤销「\(target.deviceText) · \(target.ipText)」这个会话？"
        case .kickUser(let target)?:
            return "把账号「\(target.usernameText)」的所有会话都踢下线？对方需要重新登录。"
        case .revokeOthers?:
            return "撤销后其他设备手上的令牌会立刻失效，需要重新登录；当前设备保留。"
        case nil:
            return ""
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }

    private func revoke(_ target: PanelSession) async {
        guard let client = session.client else { return }
        let wasCurrent = target.isCurrent
        let ok = await model.revoke(target, client: client)
        if ok, wasCurrent {
            // 当前会话已经被面板拉黑，留着界面只会一直 401，直接退回登录页。
            await session.forceLogout(message: "当前会话已撤销，请重新登录")
        }
    }

    private func kickAll(of target: PanelSession) async {
        guard let client = session.client else { return }
        let hitsCurrent = target.userId == session.user?.id
        _ = await model.revokeAll(of: target, client: client)
        if hitsCurrent {
            await session.forceLogout(message: "你的会话已被全部撤销，请重新登录")
        }
    }

    private func revokeOthers() async {
        guard let client = session.client else { return }
        _ = await model.revokeOthers(client: client)
    }
}

private struct SessionRow: View {
    let item: PanelSession

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isAppClient ? "iphone" : "desktopcomputer")
                .font(.system(size: 15))
                .foregroundColor(item.isCurrent ? AppTheme.success : AppTheme.idle)
                .frame(width: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.deviceText)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if item.isCurrent {
                        StatusBadge(text: "当前", color: AppTheme.success, compact: true)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.usernameText)
                        .font(.system(size: 11))
                    Text("·")
                    Text(item.ipText)
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.secondary)
                Text("登录于 \(item.createdText) · 到期 \(item.expiresText)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }
}
