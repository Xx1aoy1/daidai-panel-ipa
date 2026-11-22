import SwiftUI
import UIKit

struct MoreView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("面板数据")) {
                    NavigationLink(destination: EnvListView()) {
                        Label("环境变量", systemImage: "key.fill")
                    }
                    NavigationLink(destination: SubscriptionListView()) {
                        Label("订阅管理", systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink(destination: ScriptBrowserView()) {
                        Label("脚本文件", systemImage: "folder.fill")
                    }
                }

                Section(header: Text("服务器")) {
                    NavigationLink(destination: ServerListView()) {
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack")
                                .foregroundColor(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.currentServer?.displayName ?? "未连接")
                                    .font(.system(size: 14, weight: .medium))
                                Text(session.currentServer?.baseURL ?? "—")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    NavigationLink(destination: PanelInfoView()) {
                        Label("面板信息", systemImage: "info.circle")
                    }
                }

                Section(header: Text("账号")) {
                    if let user = session.user {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(AppTheme.accent.opacity(0.85))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                Text(user.roleText)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section(header: Text("关于")) {
                    HStack {
                        Text("客户端版本")
                        Spacer()
                        Text(AppInfo.version)
                            .foregroundColor(.secondary)
                    }
                    NavigationLink(destination: AboutView()) {
                        Label("关于呆呆面板 iOS", systemImage: "heart.text.square")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("退出后需要重新输入密码登录", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    Task { await session.logout() }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ServerListView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            Section {
                ForEach(session.servers) { server in
                    Button {
                        Task { await session.switchTo(server: server) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: session.currentServer?.id == server.id
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundColor(session.currentServer?.id == server.id
                                                 ? AppTheme.success
                                                 : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("\(server.baseURL) · \(server.username)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await session.removeServer(server) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("切换面板会尝试用已保存的令牌免密登录；令牌失效时会回到登录页。")
                    .font(.system(size: 11))
            }

            Section {
                Button {
                    session.showLogin()
                } label: {
                    Label("登录其他面板", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("服务器")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PanelInfoView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var info: PanelVersion?
    @State private var errorText: String?
    @State private var isLoading = true

    var body: some View {
        List {
            Section(header: Text("连接")) {
                KeyValueRow(label: "名称", value: session.currentServer?.displayName ?? "—")
                Divider()
                KeyValueRow(label: "地址", value: session.currentServer?.baseURL ?? "—", monospaced: true)
                Divider()
                KeyValueRow(label: "账号", value: session.currentServer?.username ?? "—")
            }

            Section(header: Text("面板")) {
                if isLoading {
                    LoadingHint(text: "读取版本…")
                } else if let info {
                    KeyValueRow(label: "版本", value: info.version ?? "未知")
                    Divider()
                    KeyValueRow(label: "API", value: info.apiVersion ?? "v1")
                    Divider()
                    KeyValueRow(label: "框架", value: info.framework ?? "gin")
                } else {
                    Text(errorText ?? "读取失败")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.failure)
                }
            }

            Section(header: Text("客户端")) {
                KeyValueRow(label: "版本", value: AppInfo.version)
                Divider()
                KeyValueRow(label: "设备", value: "\(AppInfo.deviceModel) · iOS \(AppInfo.systemVersion)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("面板信息")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let client = session.client else {
            isLoading = false
            return
        }
        do {
            info = try await client.panelVersion()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct AboutView: View {
    private let repoURL = "https://github.com/Xx1aoy1/DaidaiPanel-iOS"
    private let panelURL = "https://github.com/linzixuanzz/daidai-panel"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    AppLogo(size: 84)
                    Text("呆呆面板 iOS")
                        .font(.system(size: 19, weight: .bold))
                    Text("版本 \(AppInfo.version)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 18)

                SectionCard("关于") {
                    Text("这是一个第三方开源客户端，用来在 iPhone / iPad 上管理呆呆面板（Daidai Panel）：查看概览、运行与编辑定时任务、跟日志、改环境变量、拉订阅、看脚本。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionCard("声明") {
                    Text("本项目与呆呆面板作者无隶属关系，仅通过面板公开的 HTTP 接口通信。面板地址、账号与令牌都只保存在本机。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionCard("链接") {
                    Link(destination: URL(string: repoURL)!) {
                        HStack {
                            Label("客户端源码", systemImage: "chevron.left.forwardslash.chevron.right")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 13))
                    }
                    Divider()
                    Link(destination: URL(string: panelURL)!) {
                        HStack {
                            Label("呆呆面板主仓库", systemImage: "server.rack")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 13))
                    }
                }

                Text("MIT License")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
