import SwiftUI

struct BackupCreateView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var selection = BackupSelection.all
    @State private var isCreating = false
    @State private var errorText: String?

    /// 创建成功后把文案带回列表页，由列表显示 toast 并刷新。
    var onCreated: (String) -> Void

    private var encrypted: Bool { !password.isEmpty }
    private var canSubmit: Bool { !selection.isEmpty && !isCreating }

    var body: some View {
        Form {
            Section {
                TextField("留空则按时间命名", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("备份名称")
            } footer: {
                Text("最终文件名形如 `mybackup.tgz`（不加密）或 `mybackup.enc`（加密）。留空则由面板生成 `backup_日期_时间`。")
                    .font(.system(size: 11))
            }

            Section {
                HStack {
                    if showPassword {
                        TextField("留空则不加密", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("留空则不加密", text: $password)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("加密密码")
            } footer: {
                if encrypted {
                    Text("会用 PBKDF2 派生密钥写成 `.enc`。**密码丢了这份备份就打不开**，面板也没有找回入口，请自己记牢。")
                        .font(.system(size: 11))
                } else {
                    Text("不填就是不加密的 `.tgz`，面板里任何人都能直接恢复。备份里有环境变量和密钥，不要把明文备份到处传。")
                        .font(.system(size: 11))
                }
            }

            Section {
                ForEach(BackupItem.allCases) { item in
                    Toggle(isOn: Binding(get: { selection[item] },
                                         set: { selection[item] = $0 })) {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 14))
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                HStack {
                    Button("全选") { selection = .all }
                        .font(.system(size: 12))
                    Spacer()
                    Button("全不选") { selection = .empty }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("备份内容 · 已选 \(selection.selectedCount)/\(BackupItem.allCases.count) 项")
            } footer: {
                Text("日志体积最大，只想留配置和脚本的话可以把它关掉。依赖只记录清单，恢复后需要重新安装。")
                    .font(.system(size: 11))
            }

            if let errorText {
                Section {
                    Text(errorText)
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
                            Text("正在打包…")
                        } else {
                            Image(systemName: "externaldrive.badge.checkmark")
                            Text("开始备份")
                        }
                        Spacer()
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .disabled(!canSubmit)
            } footer: {
                if password.count > 0 && password.count < 6 {
                    Text("密码太短，建议至少 8 位。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.warning)
                } else if selection.isEmpty {
                    Text("至少选择一项要备份的内容。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.failure)
                }
            }
        }
        .navigationTitle("新建备份")
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
                let result = try await client.createBackup(name: name,
                                                           password: password,
                                                           selection: selection)
                let saved = result.filename ?? "新备份"
                onCreated("备份成功：\(saved)")
                dismiss()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            isCreating = false
        }
    }
}
