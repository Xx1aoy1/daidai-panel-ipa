import Foundation

struct PanelServer: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var username: String
    var lastLoginAt: Date?

    init(id: UUID = UUID(), name: String, baseURL: String, username: String, lastLoginAt: Date? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.lastLoginAt = lastLoginAt
    }

    var hostText: String {
        guard let url = URL(string: baseURL) else { return baseURL }
        return url.host ?? baseURL
    }

    var displayName: String {
        if !name.isEmpty { return name }
        return hostText
    }

    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

/// 全局会话：管理多台面板、登录态、令牌续期与当前客户端实例。
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var servers: [PanelServer] = []
    @Published private(set) var currentServer: PanelServer?
    @Published private(set) var user: PanelUser?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var client: APIClient?
    @Published private(set) var isRestoring = true
    @Published var sessionMessage: String?

    /// 当前账号是否允许写操作；viewer 只读，界面上对应的按钮直接不显示。
    var canWrite: Bool { user?.canWrite ?? true }

    var isViewer: Bool { user?.isViewer ?? false }

    private let serversKey = "daidai.servers"
    private let currentKey = "daidai.currentServerID"

    init() {
        loadServers()
    }

    // MARK: - 持久化

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let list = try? JSONDecoder().decode([PanelServer].self, from: data) else {
            servers = []
            return
        }
        servers = list
        if let raw = UserDefaults.standard.string(forKey: currentKey),
           let id = UUID(uuidString: raw),
           let match = list.first(where: { $0.id == id }) {
            currentServer = match
        } else {
            currentServer = list.first
        }
    }

    private func persistServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: serversKey)
        if let current = currentServer {
            UserDefaults.standard.set(current.id.uuidString, forKey: currentKey)
        }
    }

    private func upsert(_ server: PanelServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        persistServers()
    }

    // MARK: - 令牌

    private func accessKey(_ id: UUID) -> String { "access.\(id.uuidString)" }
    private func refreshKey(_ id: UUID) -> String { "refresh.\(id.uuidString)" }

    private func saveTokens(access: String?, refresh: String?, for id: UUID) {
        if let access { KeychainStore.set(access, for: accessKey(id)) }
        if let refresh, !refresh.isEmpty { KeychainStore.set(refresh, for: refreshKey(id)) }
    }

    private func clearTokens(for id: UUID) {
        KeychainStore.remove(accessKey(id))
        KeychainStore.remove(refreshKey(id))
    }

    // MARK: - 登录 / 恢复 / 退出

    func login(server input: PanelServer, password: String, totp: String?) async throws {
        let normalized = PanelServer.normalize(input.baseURL)
        guard let url = URL(string: normalized), url.host != nil else { throw PanelError.invalidURL }

        let probe = APIClient(rootURL: url, accessToken: nil, refreshToken: nil)
        let result = try await probe.login(username: input.username, password: password, totp: totp)
        guard let access = result.accessToken, !access.isEmpty else {
            throw PanelError.server(status: 200, message: "面板没有下发访问令牌", code: nil)
        }

        var stored = input
        stored.baseURL = normalized
        stored.lastLoginAt = Date()
        if stored.name.trimmingCharacters(in: .whitespaces).isEmpty {
            stored.name = url.host ?? normalized
        }
        upsert(stored)
        saveTokens(access: access, refresh: result.refreshToken, for: stored.id)
        activate(client: probe, server: stored, user: result.user)
    }

    func restore() async {
        defer { isRestoring = false }
        guard let server = currentServer ?? servers.first else { return }
        guard let access = KeychainStore.get(accessKey(server.id)) else {
            currentServer = server
            return
        }
        guard let url = URL(string: server.baseURL) else { return }
        let refresh = KeychainStore.get(refreshKey(server.id))
        let client = APIClient(rootURL: url, accessToken: access, refreshToken: refresh)
        wire(client: client, serverID: server.id)

        do {
            let user = try await client.fetchCurrentUser()
            activate(client: client, server: server, user: user)
        } catch {
            clearTokens(for: server.id)
            self.client = nil
            self.user = nil
            self.isLoggedIn = false
            currentServer = server
        }
    }

    func logout(remote: Bool = true) async {
        if remote, let client {
            try? await client.logout()
        }
        if let current = currentServer {
            clearTokens(for: current.id)
        }
        client = nil
        user = nil
        isLoggedIn = false
        sessionMessage = nil
    }

    /// 回到登录页但不清理已保存的令牌：方便临时登录另一台面板，之后还能免密切回来。
    func showLogin() {
        client = nil
        user = nil
        isLoggedIn = false
    }

    func removeServer(_ server: PanelServer) async {
        if currentServer?.id == server.id {
            await logout(remote: true)
            currentServer = nil
        }
        clearTokens(for: server.id)
        servers.removeAll { $0.id == server.id }
        if currentServer == nil { currentServer = servers.first }
        persistServers()
    }

    /// 切换到另一台已保存的面板（用已存的令牌尝试免密进入）。
    func switchTo(server: PanelServer) async {
        guard currentServer?.id != server.id else { return }
        currentServer = server
        persistServers()
        client = nil
        user = nil
        isLoggedIn = false
        isRestoring = true
        await restore()
    }

    private func activate(client: APIClient, server: PanelServer, user: PanelUser?) {
        self.client = client
        self.currentServer = server
        self.user = user
        self.isLoggedIn = true
        persistServers()
    }

    private func wire(client: APIClient, serverID: UUID) {
        client.onTokensChanged = { [weak self] access, refresh in
            self?.saveTokens(access: access, refresh: refresh, for: serverID)
        }
    }

    // MARK: - 错误处理

    /// 统一处理来自任意页面的错误：令牌彻底失效就退回登录页，其余错误交给调用方展示。
    /// 返回值表示「已被这里处理，调用方不需要再提示」。
    @discardableResult
    func handle(_ error: Error) -> Bool {
        guard let panelError = error as? PanelError else { return false }
        switch panelError {
        case .sessionExpired:
            Task { await logout(remote: false) }
            sessionMessage = "登录已失效，请重新登录"
            return true
        case .unauthorized(_, let code):
            if code == nil || code == "session_revoked" {
                Task { await logout(remote: false) }
                sessionMessage = "登录已失效，请重新登录"
                return true
            }
            return false
        default:
            return false
        }
    }

    func requireClient() throws -> APIClient {
        guard let client else { throw PanelError.missingClient }
        return client
    }
}
