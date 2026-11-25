import SwiftUI
import UniformTypeIdentifiers

/// 脚本目录的根视图：自己持有一棵树的缓存，子目录共享同一个 store。
struct ScriptBrowserRoot: View {
    @StateObject private var store = ScriptTreeStore()

    var body: some View {
        ScriptBrowserView(store: store, path: nil, title: "脚本文件")
    }
}

/// 脚本目录浏览 + 文件管理（上传 / 新建 / 改名 / 移动 / 复制 / 删除）。
///
/// 面板 `/scripts/tree` 一次给整棵树，所以这里不再按目录请求；
/// 任何写操作之后都 `store.load()` 重拉整棵树，避免父目录残留旧节点。
///
/// 弹窗统一收在 `ActiveSheet` / `PendingConfirm` 两个状态里 ——
/// iOS 15 同一视图挂多个 `.sheet` / `.confirmationDialog` 只有最后一个生效。
struct ScriptBrowserView: View {
    @EnvironmentObject private var session: SessionStore
    @ObservedObject var store: ScriptTreeStore
    /// nil 表示根目录。
    let path: String?
    let title: String

    @State private var keyword = ""
    @State private var showImporter = false
    @State private var activeSheet: ActiveSheet?
    @State private var pendingConfirm: PendingConfirm?
    @State private var workingText: String?
    @State private var toast: String?
    @State private var errorText: String?

    private var nodes: [ScriptNode] { store.nodes(at: path) }

    private var canWrite: Bool { session.canWrite }

    private var filtered: [ScriptNode] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = nodes
        guard !text.isEmpty else {
            return base.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
        }
        return base.filter { $0.displayName.lowercased().contains(text) }
    }

    var body: some View {
        Group {
            if store.isLoading && nodes.isEmpty {
                VStack {
                    LoadingHint(text: "读取脚本目录…")
                    Spacer()
                }
            } else if let message = store.errorText, nodes.isEmpty {
                VStack(spacing: 12) {
                    ErrorBanner(text: message)
                    Button("重试") { Task { await load() } }
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16)
            } else if filtered.isEmpty {
                VStack {
                    EmptyStateView(icon: "folder",
                                   title: keyword.isEmpty ? "这里没有文件" : "没有匹配的文件",
                                   message: keyword.isEmpty
                                       ? (canWrite ? "点右上角「+」新建文件、文件夹或上传。" : "面板脚本目录是空的")
                                       : "换个关键字试试")
                    Spacer()
                }
            } else {
                List {
                    if let errorText {
                        Section { ErrorBanner(text: errorText) }
                    }

                    Section {
                        ForEach(filtered) { node in
                            row(for: node)
                        }
                    } footer: {
                        if canWrite {
                            Text("长按文件可以运行、改名、移动、复制、看历史版本；左滑可直接删除。")
                                .font(.system(size: 11))
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: "筛选当前目录")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let workingText {
                    Text(workingText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if canWrite {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("上传文件", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            activeSheet = .newFile
                        } label: {
                            Label("新建文件", systemImage: "doc.badge.plus")
                        }
                        Button {
                            activeSheet = .newFolder
                        } label: {
                            Label("新建文件夹", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetView(sheet)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                prepareUpload(urls)
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .confirmationDialog(confirmTitle,
                            isPresented: Binding(get: { pendingConfirm != nil },
                                                 set: { if !$0 { pendingConfirm = nil } }),
                            titleVisibility: .visible) {
            if let pending = pendingConfirm {
                switch pending {
                case .delete(let node):
                    Button(node.isDirectory ? "删除文件夹" : "删除", role: .destructive) {
                        pendingConfirm = nil
                        Task { await delete(node) }
                    }
                case .overwrite(let upload):
                    Button("覆盖上传", role: .destructive) {
                        pendingConfirm = nil
                        Task { await performUpload(upload) }
                    }
                }
            }
            Button("取消", role: .cancel) { pendingConfirm = nil }
        }
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
        .task {
            if !store.isLoaded { await load() }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func row(for node: ScriptNode) -> some View {
        let content = ScriptNodeRow(node: node)

        if node.isDirectory {
            NavigationLink(destination: ScriptBrowserView(store: store, path: node.path, title: node.displayName)) {
                content
            }
            .contextMenu { menuItems(for: node) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canWrite {
                    Button(role: .destructive) {
                        pendingConfirm = .delete(node)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        } else if node.isEditable {
            NavigationLink(destination: ScriptEditorView(path: node.path, name: node.displayName)) {
                content
            }
            .contextMenu { menuItems(for: node) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if ScriptLanguage.canRun(path: node.path) {
                    Button {
                        activeSheet = .run(node)
                    } label: {
                        Label("运行", systemImage: "play.fill")
                    }
                    .tint(AppTheme.success)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canWrite {
                    Button(role: .destructive) {
                        pendingConfirm = .delete(node)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        activeSheet = .rename(node)
                    } label: {
                        Label("改名", systemImage: "character.cursor.ibeam")
                    }
                    .tint(AppTheme.warning)
                }
            }
        } else {
            content
                .contentShape(Rectangle())
                .onTapGesture { activeSheet = .open(node) }
                .contextMenu { menuItems(for: node) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canWrite {
                        Button(role: .destructive) {
                            pendingConfirm = .delete(node)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func menuItems(for node: ScriptNode) -> some View {
        if !node.isDirectory, ScriptLanguage.canRun(path: node.path) {
            Button {
                activeSheet = .run(node)
            } label: {
                Label("运行", systemImage: "play.fill")
            }
        }
        if !node.isDirectory {
            Button {
                activeSheet = .open(node)
            } label: {
                Label("打开", systemImage: "doc.text.magnifyingglass")
            }
        }
        if canWrite {
            Button {
                activeSheet = .rename(node)
            } label: {
                Label("重命名", systemImage: "character.cursor.ibeam")
            }
            Button {
                activeSheet = .move(node)
            } label: {
                Label("移动到…", systemImage: "folder")
            }
            Button {
                activeSheet = .copy(node)
            } label: {
                Label("复制到…", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                pendingConfirm = .delete(node)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 弹窗

    @ViewBuilder
    private func sheetView(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .newFile:
            ScriptNamePrompt(title: "新建文件",
                             placeholder: "例如 task.py",
                             confirmTitle: "创建",
                             hint: "创建在 \(currentDirText)。扩展名要是面板认识的（.py/.js/.sh/.json/.txt 等），否则保存会被拒。") { name in
                Task { await createFile(name) }
            }
        case .newFolder:
            ScriptNamePrompt(title: "新建文件夹",
                             placeholder: "例如 mytasks",
                             confirmTitle: "创建",
                             hint: "创建在 \(currentDirText)。") { name in
                Task { await createFolder(name) }
            }
        case .rename(let node):
            ScriptNamePrompt(title: "重命名",
                             placeholder: "新名称",
                             confirmTitle: "改名",
                             hint: "只改文件名，不能改它所在的目录（要换目录请用「移动到…」）。",
                             initialValue: node.displayName) { name in
                Task { await rename(node, to: name) }
            }
        case .move(let node):
            ScriptDirectoryPicker(store: store,
                                  title: "移动「\(node.displayName)」",
                                  currentDir: ScriptPath.dir(of: node.path)) { dir in
                Task { await move(node, to: dir) }
            }
        case .copy(let node):
            ScriptCopySheet(store: store, sourcePath: node.path) { dir, name in
                Task { await copy(node, to: dir, name: name) }
            }
        case .open(let node):
            NavigationView {
                ScriptEditorView(path: node.path, name: node.displayName)
                    .environmentObject(session)
            }
            .navigationViewStyle(.stack)
        case .run(let node):
            ScriptRunView(title: node.displayName, source: .saved(path: node.path))
                .environmentObject(session)
        }
    }

    // MARK: - 文案

    private var currentDirText: String {
        guard let path, !path.isEmpty else { return "脚本根目录" }
        return path
    }

    private var confirmTitle: String {
        guard let pending = pendingConfirm else { return "" }
        switch pending {
        case .delete(let node):
            if node.isDirectory {
                return "删除文件夹「\(node.displayName)」？里面的文件会一起删掉，无法恢复。"
            }
            return "删除「\(node.displayName)」？这个操作不可撤销。"
        case .overwrite(let upload):
            return "这些文件已存在：\(upload.conflicts.joined(separator: "、"))。继续上传会直接覆盖，没有撤销。"
        }
    }

    // MARK: - 动作

    private func load() async {
        guard let client = session.client else { return }
        await store.load(client: client)
    }

    private func createFile(_ name: String) async {
        guard let client = session.client else { return }
        let target = store.join(dir: path, name: name)
        workingText = "创建中"
        do {
            try await client.saveScriptContent(path: target, content: "")
            await load()
            flash("已创建 \(name)")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    private func createFolder(_ name: String) async {
        guard let client = session.client else { return }
        let target = store.join(dir: path, name: name)
        workingText = "创建中"
        do {
            try await client.createScriptDirectory(path: target)
            await load()
            flash("已创建 \(name)")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    private func rename(_ node: ScriptNode, to name: String) async {
        guard let client = session.client else { return }
        guard name != node.displayName else { return }
        workingText = "改名中"
        do {
            let newPath = try await client.renameScript(path: node.path, newName: name)
            await load()
            flash("已改名为 \(newPath.map(ScriptPath.leaf) ?? name)")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    private func move(_ node: ScriptNode, to dir: String) async {
        guard let client = session.client else { return }
        workingText = "移动中"
        do {
            _ = try await client.moveScript(path: node.path, targetDir: dir)
            await load()
            flash("已移动到 \(dir.isEmpty ? "根目录" : dir)")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    private func copy(_ node: ScriptNode, to dir: String, name: String) async {
        guard let client = session.client else { return }
        workingText = "复制中"
        do {
            let newPath = try await client.copyScript(path: node.path, targetDir: dir, newName: name)
            await load()
            flash("已复制到 \(newPath ?? name)")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    private func delete(_ node: ScriptNode) async {
        guard let client = session.client else { return }
        workingText = "删除中"
        do {
            try await client.deleteScript(path: node.path, isDirectory: node.isDirectory)
            await load()
            flash("已删除 \(node.displayName)")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    /// 读文件内容（fileImporter 给的是安全作用域 URL，必须先 startAccessing）。
    private func prepareUpload(_ urls: [URL]) {
        var files: [ScriptUploadFile] = []
        var rejected: [String] = []

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let name = url.lastPathComponent
            guard ScriptPath.isAllowedUpload(name) else {
                rejected.append(name)
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                rejected.append(name)
                continue
            }
            if data.count > 100 * 1024 * 1024 {
                rejected.append("\(name)（超过 100MB）")
                continue
            }
            files.append(ScriptUploadFile(filename: name,
                                          mimeType: "application/octet-stream",
                                          data: data))
        }

        if !rejected.isEmpty {
            errorText = "这些文件没上传：\(rejected.joined(separator: "、"))（面板只认脚本/文本/图片类扩展名，单个上限 100MB）"
        }
        guard !files.isEmpty else { return }

        let existing = Set(nodes.filter { !$0.isDirectory }.map { $0.displayName })
        let conflicts = files.map { $0.filename }.filter { existing.contains($0) }
        let upload = PendingUpload(files: files, conflicts: conflicts)
        if conflicts.isEmpty {
            Task { await performUpload(upload) }
        } else {
            pendingConfirm = .overwrite(upload)
        }
    }

    private func performUpload(_ upload: PendingUpload) async {
        guard let client = session.client else { return }
        workingText = "上传中"
        do {
            let result = try await client.uploadScriptFiles(upload.files, dir: path ?? "")
            await load()
            flash(result.message ?? "已上传 \(upload.files.count) 个文件")
        } catch {
            handle(error)
        }
        workingText = nil
    }

    private func handle(_ error: Error) {
        if !session.handle(error) {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 辅助类型

private enum ActiveSheet: Identifiable {
    case newFile
    case newFolder
    case rename(ScriptNode)
    case move(ScriptNode)
    case copy(ScriptNode)
    case open(ScriptNode)
    case run(ScriptNode)

    var id: String {
        switch self {
        case .newFile: return "newFile"
        case .newFolder: return "newFolder"
        case .rename(let node): return "rename-\(node.path)"
        case .move(let node): return "move-\(node.path)"
        case .copy(let node): return "copy-\(node.path)"
        case .open(let node): return "open-\(node.path)"
        case .run(let node): return "run-\(node.path)"
        }
    }
}

private enum PendingConfirm: Identifiable {
    case delete(ScriptNode)
    case overwrite(PendingUpload)

    var id: String {
        switch self {
        case .delete(let node): return "delete-\(node.path)"
        case .overwrite(let upload): return "overwrite-\(upload.id)"
        }
    }
}

private struct PendingUpload {
    let id = UUID()
    let files: [ScriptUploadFile]
    let conflicts: [String]
}

private struct ScriptNodeRow: View {
    let node: ScriptNode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: node.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(node.isDirectory ? AppTheme.warning : AppTheme.accent)
                .frame(width: 20)

            Text(node.displayName)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer(minLength: 4)

            if !node.isDirectory, !node.sizeText.isEmpty {
                Text(node.sizeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if node.isDirectory, let children = node.children {
                Text("\(children.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
