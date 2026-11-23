import SwiftUI

struct BackupDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let backup: PanelBackup
    /// 删除成功后通知列表刷新。
    var onChanged: () -> Void

    @State private var shareFile: ShareFile?
    @State private var isDownloading = false
    @State private var showDeleteConfirm = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section(header: Text("备份信息")) {
                KeyValueRow(label: "文件名", value: backup.name, monospaced: true)
                Divider()
                KeyValueRow(label: "大小", value: backup.sizeText)
                Divider()
                KeyValueRow(label: "类型", value: backup.kindText + (backup.isEncrypted ? "（需密码）" : "（明文）"))
                Divider()
                KeyValueRow(label: "创建时间", value: backup.timeText)
            }

            Section {
                NavigationLink {
                    BackupRestoreView(backup: backup)
                        .environmentObject(session)
                } label: {
                    Label("用这份备份恢复", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.warning)
                }

                Button {
                    download()
                } label: {
                    HStack {
                        Label("下载到本机", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15))
                        Spacer()
                        if isDownloading { ProgressView().scaleEffect(0.8) }
                    }
                }
                .disabled(isDownloading)
            } header: {
                Text("操作")
            } footer: {
                Text("恢复是整库替换：勾选的内容会被备份里的数据覆盖，未勾选的内容保持现状。下载会把文件存到临时目录再交给系统分享面板，可以存进「文件」App。")
                    .font(.system(size: 11))
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除这份备份", systemImage: "trash")
                        .font(.system(size: 15))
                }
            } footer: {
                Text("删除只是把备份文件从磁盘上移除，不会影响当前正在运行的面板数据。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("备份详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .confirmationDialog("删除后这份备份文件会从面板磁盘上移除，无法找回。",
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除备份", role: .destructive) { deleteBackup() }
            Button("取消", role: .cancel) {}
        }
    }

    private func download() {
        guard let client = session.client else { return }
        isDownloading = true
        errorText = nil
        Task {
            do {
                let url = try await client.downloadBackup(filename: backup.name)
                shareFile = ShareFile(url: url)
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
            isDownloading = false
        }
    }

    private func deleteBackup() {
        guard let client = session.client else { return }
        Task {
            do {
                _ = try await client.deleteBackup(filename: backup.name)
                onChanged()
                dismiss()
            } catch {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
    }
}
