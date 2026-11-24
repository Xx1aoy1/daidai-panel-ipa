import SwiftUI

@MainActor
final class PasskeyListViewModel: ObservableObject {
    @Published var passkeys: [PasskeyEntry] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toast: String?

    func reload(client: APIClient) async {
        if passkeys.isEmpty { isLoading = true }
        errorText = nil
        do {
            passkeys = try await client.fetchPasskeys()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func rename(_ target: PasskeyEntry, to name: String, client: APIClient) async {
        do {
            let message = try await client.renamePasskey(id: target.id, name: name)
            flash(message ?? "已重命名")
            await reload(client: client)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    func delete(_ target: PasskeyEntry, client: APIClient) async {
        do {
            let message = try await client.deletePasskey(id: target.id)
            flash(message ?? "已删除")
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

/// 通行密钥：面板只做了网页端的注册流程，APP 里只能**看、改名、删**。
///
/// 注册要跑完整的 WebAuthn 仪式（浏览器弹系统验证、认证器回传 attestation），
/// 还要求凭据绑定的域名能托管 `apple-app-site-association`；面板多半是内网 IP 访问，
/// 这两条都不成立，所以这里不假装能加，直接把入口指向网页端。
struct PasskeyView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = PasskeyListViewModel()

    @State private var renameTarget: PasskeyEntry?
    @State private var renameText = ""
    @State private var deleteTarget: PasskeyEntry?

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.accent)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("用指纹 / 面容 / 设备 PIN 登录网页端")
                            .font(.system(size: 13, weight: .medium))
                        Text("通行密钥登录会直接通过验证，不再输两步验证码；密码登录照常可用。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("说明")
            }

            Section {
                if model.isLoading && model.passkeys.isEmpty {
                    LoadingHint(text: "读取通行密钥…")
                } else if model.passkeys.isEmpty {
                    VStack(spacing: 8) {
                        EmptyStateView(icon: "key.slash",
                                       title: "还没有通行密钥",
                                       message: "添加要在浏览器里完成（WebAuthn 只支持网页端），加完这里就能看到并管理。")
                        if let url = session.currentServer?.url {
                            Link(destination: url) {
                                Label("在浏览器打开面板添加", systemImage: "safari")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(model.passkeys) { passkey in
                        PasskeyRow(passkey: passkey)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = passkey
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    renameText = passkey.nameText
                                    renameTarget = passkey
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .tint(AppTheme.accent)
                            }
                    }
                }
            } header: {
                Text(model.passkeys.isEmpty ? "我的通行密钥" : "我的通行密钥（\(model.passkeys.count)）")
            } footer: {
                Text("每枚凭据绑定添加时的地址（含端口），换成 IP 或换端口访问都用不了；改密码 / 重置密码会把它们全部清掉。APP 端暂不支持添加通行密钥。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通行密钥")
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
        .alert("重命名通行密钥", isPresented: renameBinding) {
            TextField("名称", text: $renameText)
            Button("保存") {
                guard let target = renameTarget else { return }
                let name = renameText
                renameTarget = nil
                Task { await rename(target, to: name) }
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        } message: {
            Text("只改显示名，凭据本身不动。超过 64 字会被面板截断。")
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible) {
            Button("删除这枚通行密钥", role: .destructive) {
                guard let target = deleteTarget else { return }
                deleteTarget = nil
                Task { await delete(target) }
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteTitle: String {
        guard let target = deleteTarget else { return "" }
        return "删除「\(target.nameText)」？删完这枚凭据就登不了了，要重新在浏览器里加一遍。"
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.reload(client: client)
    }

    private func rename(_ target: PasskeyEntry, to name: String) async {
        guard let client = session.client else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            model.errorText = "名称不能为空"
            return
        }
        await model.rename(target, to: trimmed, client: client)
    }

    private func delete(_ target: PasskeyEntry) async {
        guard let client = session.client else { return }
        await model.delete(target, client: client)
    }
}

private struct PasskeyRow: View {
    let passkey: PasskeyEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: passkey.isSynced ? "key.icloud.fill" : "key.fill")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(passkey.nameText)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if passkey.isSynced {
                        StatusBadge(text: "已同步", color: AppTheme.success, compact: true)
                    }
                }

                Text(passkey.hostText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Text("添加 \(passkey.createdText)")
                    Text("·")
                    Text("上次使用 \(passkey.lastUsedText)")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }
}
