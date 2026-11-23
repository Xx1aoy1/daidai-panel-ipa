import SwiftUI

struct UserCreateView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var role: PanelRole = .operator
    @State private var isCreating = false
    @State private var errorText: String?

    var onCreated: (String) -> Void

    private var localError: String? {
        if let nameError = AccountRules.validateUsername(username) { return nameError }
        if let pwdError = AccountRules.validatePassword(password) { return pwdError }
        if password != confirmPassword { return "两次输入的密码不一致" }
        return nil
    }

    var body: some View {
        Form {
            Section {
                TextField("用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("账号")
            } footer: {
                Text("1-32 位，支持中文、字母、数字和下划线。")
                    .font(.system(size: 11))
            }

            Section {
                SecureField("密码", text: $password)
                SecureField("再输一次", text: $confirmPassword)
            } header: {
                Text("密码")
            } footer: {
                Text("8-72 位（UTF-8 不超过 72 字节，一个汉字占 3 字节），字母 / 数字 / 符号至少含两种。")
                    .font(.system(size: 11))
            }

            Section {
                ForEach(PanelRole.allCases) { item in
                    Button {
                        role = item
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: role == item ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(role == item ? AppTheme.accent : .secondary)
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
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("角色")
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
                    create()
                } label: {
                    HStack {
                        Spacer()
                        if isCreating {
                            ProgressView().scaleEffect(0.85)
                            Text("正在创建…")
                        } else {
                            Image(systemName: "person.badge.plus")
                            Text("创建账号")
                        }
                        Spacer()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .disabled(isCreating || localError != nil)
            }
        }
        .navigationTitle("新建账号")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isCreating)
            }
        }
    }

    private func create() {
        guard let client = session.client else { return }
        errorText = nil
        isCreating = true
        Task {
            do {
                let account = try await client.createUser(username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                                          password: password,
                                                          role: role)
                onCreated("已创建「\(account?.username ?? username)」（\(role.title)）")
                dismiss()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            isCreating = false
        }
    }
}
