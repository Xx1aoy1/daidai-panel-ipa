import SwiftUI

@MainActor
final class SecurityCenterViewModel: ObservableObject {
    @Published var twoFAEnabled: Bool?
    @Published var stats: LoginStats?
    @Published var sessionCount: Int?
    @Published var whitelistCount: Int?
    @Published var errorText: String?
    @Published var isLoading = false

    /// 四个接口逐个 try：任何一个 403 / 超时都不该把整页拖成空白。
    func load(client: APIClient, isAdmin: Bool) async {
        if twoFAEnabled == nil { isLoading = true }
        errorText = nil

        do {
            let status = try await client.fetchTwoFactorStatus()
            twoFAEnabled = status.isEnabled
        } catch {
            if !isAdmin { errorText = (error as? PanelError)?.message ?? error.localizedDescription }
        }

        guard isAdmin else {
            isLoading = false
            return
        }

        var failures: [String] = []
        do {
            stats = try await client.fetchLoginStats(days: 7)
        } catch {
            failures.append(message(of: error))
        }
        do {
            sessionCount = try await client.fetchSessions().count
        } catch {
            failures.append(message(of: error))
        }
        do {
            whitelistCount = try await client.fetchIPWhitelist().count
        } catch {
            failures.append(message(of: error))
        }
        if let first = failures.first { errorText = first }
        isLoading = false
    }

    private func message(of error: Error) -> String {
        (error as? PanelError)?.message ?? error.localizedDescription
    }
}

/// 安全中心：两步验证（所有角色）+ 登录日志 / 活动会话 / IP 白名单（仅 admin）。
struct SecurityCenterView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SecurityCenterViewModel()

    private var isAdmin: Bool { session.user?.isAdmin == true }

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if isAdmin, let stats = model.stats {
                Section {
                    HStack(spacing: 10) {
                        StatTile(title: "近 \(stats.days) 天登录",
                                 value: "\(stats.total)",
                                 subtitle: "成功 \(stats.success) · 失败 \(stats.failed)",
                                 tint: AppTheme.accent,
                                 systemImage: "person.badge.key.fill")
                        StatTile(title: "活跃会话",
                                 value: model.sessionCount.map { "\($0)" } ?? "\(stats.sessions)",
                                 subtitle: "到期自动失效",
                                 tint: AppTheme.success,
                                 systemImage: "rectangle.stack.person.crop")
                        StatTile(title: "锁定账号",
                                 value: "\(stats.locked)",
                                 subtitle: "多次输错密码",
                                 tint: stats.locked > 0 ? AppTheme.failure : AppTheme.idle,
                                 systemImage: "lock.slash.fill")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("概览")
                }
            }

            Section {
                NavigationLink(destination: TwoFactorView()) {
                    row(title: "两步验证",
                        icon: "lock.shield.fill",
                        tint: twoFATint,
                        detail: twoFAText,
                        badge: model.twoFAEnabled == true ? ("已启用", AppTheme.success) : ("未启用", AppTheme.idle))
                }
            } header: {
                Text("我的账号")
            } footer: {
                Text("两步验证只作用于当前登录的账号，任何角色都能自己开；开启后登录要多输一次认证器里的 6 位动态码。")
                    .font(.system(size: 11))
            }

            Section {
                if isAdmin {
                    NavigationLink(destination: LoginLogListView()) {
                        row(title: "登录日志",
                            icon: "list.bullet.rectangle.portrait.fill",
                            tint: AppTheme.accent,
                            detail: model.stats.map { "近 \($0.days) 天 \($0.total) 条" } ?? "查看登录记录",
                            badge: nil)
                    }
                    NavigationLink(destination: SessionListView()) {
                        row(title: "活动会话",
                            icon: "rectangle.stack.person.crop.fill",
                            tint: AppTheme.running,
                            detail: model.sessionCount.map { "\($0) 个有效会话" } ?? "查看在线设备",
                            badge: nil)
                    }
                    NavigationLink(destination: IPWhitelistView()) {
                        row(title: "IP 白名单",
                            icon: "network.badge.shield.half.filled",
                            tint: AppTheme.warning,
                            detail: whitelistText,
                            badge: (model.whitelistCount ?? 0) > 0 ? ("限制中", AppTheme.failure) : ("不限制", AppTheme.idle))
                    }
                } else {
                    lockedRow("登录日志", icon: "list.bullet.rectangle.portrait.fill")
                    lockedRow("活动会话", icon: "rectangle.stack.person.crop.fill")
                    lockedRow("IP 白名单", icon: "network.badge.shield.half.filled")
                }
            } header: {
                Text("管理员")
            } footer: {
                if !isAdmin {
                    Text("登录日志、活动会话、IP 白名单这三组接口面板只对管理员开放，当前账号调用会 403，所以这里不开放入口。")
                        .font(.system(size: 11))
                } else {
                    Text("活动会话能看到所有人的登录，包括网页端；IP 白名单一旦非空就立刻生效，加之前先确认你自己的出口 IP 在列表里。")
                        .font(.system(size: 11))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("安全")
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
    }

    private var twoFAText: String {
        switch model.twoFAEnabled {
        case .some(true): return "登录需要动态验证码"
        case .some(false): return "建议开启，防密码泄露"
        case .none: return "状态未知"
        }
    }

    private var twoFATint: Color {
        model.twoFAEnabled == true ? AppTheme.success : AppTheme.warning
    }

    private var whitelistText: String {
        guard let count = model.whitelistCount else { return "登录来源限制" }
        return count == 0 ? "空列表：不限制来源" : "\(count) 条，仅列表内可登录"
    }

    private func row(title: String,
                     icon: String,
                     tint: Color,
                     detail: String,
                     badge: (String, Color)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let badge {
                StatusBadge(text: badge.0, color: badge.1, compact: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func lockedRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text("需管理员")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client, isAdmin: isAdmin)
    }
}
