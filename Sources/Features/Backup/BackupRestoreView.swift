import SwiftUI

struct BackupRestoreView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let backup: PanelBackup

    private enum Phase: Equatable {
        case idle
        case running
        case done
        case failed
    }

    @State private var phase: Phase = .idle
    @State private var password = ""
    @State private var showPassword = false
    @State private var confirmText = ""
    @State private var progress: RestoreProgress?
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var showRestartConfirm = false

    /// 面板要求手动输入，避免手滑点一下就整库覆盖。
    private var confirmWord: String { "恢复" }
    private var confirmed: Bool { confirmText.trimmingCharacters(in: .whitespaces) == confirmWord }
    private var canStart: Bool {
        phase == .idle || phase == .failed
    }

    var body: some View {
        List {
            Section(header: Text("将要恢复")) {
                KeyValueRow(label: "文件", value: backup.name, monospaced: true)
                Divider()
                KeyValueRow(label: "大小", value: backup.sizeText)
                Divider()
                KeyValueRow(label: "创建时间", value: backup.shortTimeText)
            }

            if backup.isEncrypted {
                Section {
                    HStack {
                        if showPassword {
                            TextField("备份密码", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("备份密码", text: $password)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .disabled(phase == .running || phase == .done)
                } header: {
                    Text("解密密码")
                } footer: {
                    Text("这份备份是 `.enc` 加密的，密码就是当初创建时设置的那个，面板没有找回入口。")
                        .font(.system(size: 11))
                }
            }

            warningSection

            if phase == .idle || phase == .failed {
                Section {
                    TextField("输入「\(confirmWord)」以确认", text: $confirmText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("二次确认")
                } footer: {
                    Text("恢复中途不要关闭 App 或切走面板。面板侧是同步执行的，整库替换完成前接口不会返回。")
                        .font(.system(size: 11))
                }

                Section {
                    Button {
                        start()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "exclamationmark.arrow.circlepath")
                            Text(phase == .failed ? "重试恢复" : "开始恢复")
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(!confirmed || (backup.isEncrypted && password.isEmpty))
                } footer: {
                    if backup.isEncrypted && password.isEmpty {
                        Text("先填备份密码。")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.warning)
                    } else if !confirmed {
                        Text("在输入框里键入「\(confirmWord)」才能点这个按钮。")
                            .font(.system(size: 11))
                    }
                }
            }

            if phase == .running || phase == .done || phase == .failed {
                progressSection
            }

            if phase == .done {
                doneSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("恢复备份")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { pollTask?.cancel() }
        .confirmationDialog("面板会重启一次，连接会短暂中断，之后需要用账号重新登录。",
                            isPresented: $showRestartConfirm,
                            titleVisibility: .visible) {
            Button("重启面板") { restart() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 分区

    private var warningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("这会覆盖现有数据", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.failure)

                Text("备份里勾选了哪几类，那几类就会被整表替换：配置、任务、订阅、变量、日志、脚本、依赖清单、任务视图。没勾选的保持现状。覆盖之后原始数据不再保留，操作不可撤销——先做一份当前状态的备份再恢复，是唯一的安全网。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("另外：备份里有账号表时，用户与密码也会被一起替换，恢复完当前的登录态大概率失效。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } header: {
            Text("风险提示")
        }
    }

    private var progressSection: some View {
        Section(header: Text("进度")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(progress?.stageText ?? (phase == .done ? "恢复完成" : "正在连接面板…"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(progress?.percentValue ?? (phase == .done ? 100 : 0)))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ProgressView(value: progress?.percentValue ?? (phase == .done ? 100 : 0), total: 100)
                    .tint(phase == .failed ? AppTheme.failure : AppTheme.accent)

                if let source = progress?.sourceText {
                    Text(source)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if phase == .done {
                    Label("数据已恢复完成", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.success)
                }

                if phase == .failed, let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.failure)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var doneSection: some View {
        Section {
            Button {
                Task { await session.logout() }
            } label: {
                Label("重新登录", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 15, weight: .medium))
            }

            Button {
                showRestartConfirm = true
            } label: {
                Label("重启面板让配置生效", systemImage: "arrow.clockwise")
                    .font(.system(size: 15))
            }
        } header: {
            Text("下一步")
        } footer: {
            Text("恢复只写入数据库与文件，运行中的进程还拿着旧配置。重启一次最稳妥；不重启也能用，大部分设置在下次操作时生效。重启后面板会断开十几秒。")
                .font(.system(size: 11))
        }
    }

    // MARK: - 动作

    @MainActor
    private func start() {
        guard let client = session.client else { return }
        errorText = nil
        progress = nil
        phase = .running

        let filename = backup.name
        let pwd = password

        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if let snapshot = try? await client.fetchRestoreProgress() {
                    progress = snapshot
                    if snapshot.isCompleted {
                        if phase == .running { phase = .done }
                        return
                    }
                    if snapshot.isFailed {
                        if phase == .running {
                            errorText = snapshot.error ?? "恢复失败"
                            phase = .failed
                        }
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }

        Task {
            do {
                _ = try await client.restoreBackup(filename: filename, password: pwd)
                // 接口返回时进度表可能还没写上 completed，给轮询一点收尾时间。
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if phase == .running { phase = .done }
            } catch {
                if phase == .running {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                    phase = .failed
                    pollTask?.cancel()
                }
            }
        }
    }

    private func restart() {
        guard let client = session.client else { return }
        Task {
            do {
                try await client.restartPanel()
            } catch {
                // 重启会主动断开连接，这里报错是正常现象，不当失败处理。
            }
            await session.logout(remote: false)
        }
    }
}
