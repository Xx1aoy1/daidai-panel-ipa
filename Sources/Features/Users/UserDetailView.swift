import SwiftUI

struct UserDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let onChanged: () -> Void

    @State private var account: PanelAccount
    @State private var pendingRole: PanelRole?
    @State private var showDeleteConfirm = false
    @State private var showResetPassword = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var toast: String?

    init(account: PanelAccount, onChanged: @escaping () -> Void) {
        self.onChanged = onChanged
        _account = State(initialValue: account)
    }

    private var isMe: Bool { account.id == session.user?.id }

    var body: some View {
        List {
            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section(header: Text("账号信息")) {
                KeyValueRow(label: "用户名", value: account.username, monospaced: true)
                Divider()
                KeyValueRow(label: "用户 ID", value: "\(account.id)")
                Divider()
                KeyValueRow(label: "最后登录", value: account.lastLoginText)
                Divider()
                KeyValueRow(label: "创建时间", value: account.createdText)
                Divider()
                KeyValueRow(label: "两步验证", value: account.twoFactorEnabled == true ? "已开启" : "未开启")
            }

            Section {
                ForEach(PanelRole.allCases) { item in
                    Button {
                        guard item != account.roleValue else { return }
                        pendingRole = item
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: account.roleValue == item ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(account.roleValue == item ? AppTheme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if busy && pendingRole == item { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            } header: {
                Text("角色")
            } footer: {
                if isMe {
                    Text("这是你自己的账号。改角色会清掉你自己的登录会话，下次请求就要重新登录；降成运维后管理类页面会全部消失。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.warning)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { account.isEnabled },
                                    set: { newValue in
                                        guard newValue != account.isEnabled else { return }
                                        setEnabled(newValue)
                                    })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许登录")
                            .font(.system(size: 14))
                        Text(account.isEnabled ? "账号正常，可以登录面板" : "账号已禁用，登录会被拒绝，现有会话也已撤销")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(busy || (isMe && account.isEnabled))
            } header: {
                Text("状态")
            } footer: {
                if isMe && account.isEnabled {
                    Text("不能禁用自己，否则会立刻把自己锁在门外。要停用请用另一个管理员账号操作。")
                        .font(.system(size: 11))
                }
            }

            Section {
                Button {
                    showResetPassword = true
                } label: {
                    Label("重置密码", systemImage: "key.horizontal.fill")
                        .font(.system(size: 15))
                }
                .disabled(busy)
            } footer: {
                Text("重置后该账号的全部会话会被撤销，已绑定的通行密钥也会一并清除（面板侧行为）。")
                    .font(.system(size: 11))
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除账号", systemImage: "person.crop.circle.badge.minus")
                        .font(.system(size: 15))
                }
                .disabled(busy || isMe)
            } footer: {
                Text(isMe ? "不能删除当前登录的账号，面板会直接回「不能删除自己」。" : "删除会连同该账号的通行密钥一起移除，且无法恢复。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.username)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast {
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
        .sheet(isPresented: $showResetPassword) {
            NavigationView {
                UserResetPasswordView(account: account) { message in
                    flash(message)
                    onChanged()
                }
                .environmentObject(session)
            }
            .navigationViewStyle(.stack)
        }
        .confirmationDialog(roleConfirmTitle, isPresented: Binding(
            get: { pendingRole != nil },
            set: { if !$0 { pendingRole = nil } }), titleVisibility: .visible) {
            Button("确认修改") {
                if let role = pendingRole {
                    pendingRole = nil
                    changeRole(role)
                }
            }
            Button("取消", role: .cancel) { pendingRole = nil }
        }
        .confirmationDialog("删除后这个账号无法登录，通行密钥一并清除，且不可恢复。",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除账号", role: .destructive) { deleteAccount() }
            Button("取消", role: .cancel) {}
        }
    }

    private var roleConfirmTitle: String {
        guard let role = pendingRole else { return "" }
        if isMe {
            return "把自己改成「\(role.title)」：提交后你自己的会话会被立即撤销，需要重新登录。"
        }
        return "把「\(account.username)」改成「\(role.title)」：该用户的所有设备会被立即踢下线。"
    }

    private func changeRole(_ role: PanelRole) {
        guard let client = session.client else { return }
        busy = true
        errorText = nil
        Task {
            do {
                if let updated = try await client.updateUser(id: account.id, role: role, enabled: nil) {
                    account = updated
                } else {
                    account = PanelAccount(id: account.id,
                                           username: account.username,
                                           role: role.rawValue,
                                           enabled: account.enabled,
                                           avatarUrl: account.avatarUrl,
                                           lastLoginAt: account.lastLoginAt,
                                           createdAt: account.createdAt,
                                           updatedAt: account.updatedAt,
                                           twoFactorEnabled: account.twoFactorEnabled)
                }
                flash("角色已改为「\(role.title)」")
                onChanged()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard let client = session.client else { return }
        busy = true
        errorText = nil
        Task {
            do {
                if let updated = try await client.updateUser(id: account.id, role: nil, enabled: enabled) {
                    account = updated
                }
                flash(enabled ? "已启用" : "已禁用并踢下线")
                onChanged()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func deleteAccount() {
        guard let client = session.client else { return }
        busy = true
        errorText = nil
        Task {
            do {
                _ = try await client.deleteUser(id: account.id)
                onChanged()
                dismiss()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            busy = false
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// 重置密码：面板没有「旧密码」这一步，管理员直接写新密码。
struct UserResetPasswordView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let account: PanelAccount
    var onDone: (String) -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorText: String?

    private var localError: String? {
        if let detail = AccountRules.validatePassword(password) { return detail }
        if password != confirmPassword { return "两次输入的密码不一致" }
        return nil
    }

    var body: some View {
        Form {
            Section {
                SecureField("新密码", text: $password)
                SecureField("再输一次", text: $confirmPassword)
            } header: {
                Text("为「\(account.username)」设置新密码")
            } footer: {
                Text("8-72 位，字母 / 数字 / 符号至少含两种。重置后该账号的所有设备会立刻掉线。")
                    .font(.system(size: 11))
            }

            if let message = errorText ?? localError {
                Section {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.failure)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().scaleEffect(0.85)
                            Text("正在重置…")
                        } else {
                            Text("重置密码")
                        }
                        Spacer()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .disabled(isSaving || localError != nil)
            }
        }
        .navigationTitle("重置密码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isSaving)
            }
        }
    }

    private func submit() {
        guard let client = session.client else { return }
        errorText = nil
        isSaving = true
        Task {
            do {
                let message = try await client.resetUserPassword(id: account.id, password: password)
                onDone(message ?? "密码已重置")
                dismiss()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
