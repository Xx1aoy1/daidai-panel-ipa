import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BackupListViewModel: ObservableObject {
    @Published var backups: [PanelBackup] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var errorText: String?
    @Published var toast: String?
    @Published var busyName: String?

    var totalSize: Double {
        backups.reduce(0) { $0 + Double($1.size ?? 0) }
    }

    func load(client: APIClient) async {
        if backups.isEmpty { isLoading = true }
        errorText = nil
        do {
            let loaded = try await client.fetchBackups()
            backups = loaded.sorted { lhs, rhs in
                let left = DateParser.parse(lhs.createdAt) ?? .distantPast
                let right = DateParser.parse(rhs.createdAt) ?? .distantPast
                return left > right
            }
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ backup: PanelBackup, client: APIClient) async -> Bool {
        busyName = backup.name
        do {
            _ = try await client.deleteBackup(filename: backup.name)
            backups.removeAll { $0.name == backup.name }
            flash("已删除「\(backup.name)」")
            busyName = nil
            return true
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            busyName = nil
            return false
        }
    }

    func upload(url: URL, client: APIClient) async {
        let name = url.lastPathComponent.lowercased()
        guard name.hasSuffix(".json") || name.hasSuffix(".enc")
                || name.hasSuffix(".tgz") || name.hasSuffix(".tar.gz") else {
            errorText = "只能上传 .json / .enc / .tgz / .tar.gz 备份文件"
            return
        }
        isUploading = true
        errorText = nil
        do {
            let saved = try await client.uploadBackup(fileURL: url)
            flash("上传成功：\(saved ?? url.lastPathComponent)")
            await load(client: client)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isUploading = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct BackupListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = BackupListViewModel()

    @State private var showCreate = false
    @State private var showImporter = false
    @State private var pendingDelete: PanelBackup?

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if model.isLoading && model.backups.isEmpty {
                LoadingHint(text: "读取备份列表…")
                    .listRowBackground(Color.clear)
            } else if model.backups.isEmpty {
                EmptyStateView(icon: "externaldrive",
                               title: "还没有备份",
                               message: "点右上角「+」把配置、任务、变量、脚本打包成一份，之后随时可以整库恢复")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.backups) { backup in
                        NavigationLink {
                            BackupDetailView(backup: backup) {
                                Task { await reload() }
                            }
                            .environmentObject(session)
                        } label: {
                            BackupRow(backup: backup, busy: model.busyName == backup.name)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = backup
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("共 \(model.backups.count) 份 · \(Bytes.text(model.totalSize))")
                } footer: {
                    Text("备份文件存在面板的 data/backups 目录里。带锁标记的 .enc 需要当初设置的密码才能恢复，密码丢了就打不开。")
                        .font(.system(size: 11))
                }
            }

            Section {
                Button {
                    showCreate = true
                } label: {
                    Label("立即备份", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                }

                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Label("从文件上传备份", systemImage: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        if model.isUploading { ProgressView().scaleEffect(0.8) }
                    }
                }
                .disabled(model.isUploading)
            } footer: {
                Text("上传支持面板自己导出的 .tgz / .enc，也支持旧版 .json，以及青龙导出的备份（面板会自动识别并转换）。单个文件上限 512MB。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("备份与恢复")
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
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationView {
                BackupCreateView { message in
                    model.toast = message
                    Task { await reload() }
                }
                .environmentObject(session)
            }
            .navigationViewStyle(.stack)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, let client = session.client else { return }
                Task { await model.upload(url: url, client: client) }
            case .failure(let error):
                Task { @MainActor in
                    model.errorText = error.localizedDescription
                }
            }
        }
        .confirmationDialog("删除后这份备份文件会从面板磁盘上移除，无法找回。",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除备份", role: .destructive) {
                guard let backup = pendingDelete else { return }
                pendingDelete = nil
                guard let client = session.client else { return }
                Task { _ = await model.delete(backup, client: client) }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }
}

private struct BackupRow: View {
    let backup: PanelBackup
    let busy: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: backup.kindIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(backup.isEncrypted ? AppTheme.warning : AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(backup.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(backup.sizeText)
                    Text("·")
                    Text(backup.shortTimeText)
                    if backup.isEncrypted {
                        Text("· 需密码")
                            .foregroundColor(AppTheme.warning)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            if busy { ProgressView().scaleEffect(0.7) }
        }
        .padding(.vertical, 2)
    }
}
