import SwiftUI

/// 脚本目录浏览。根目录从 `/scripts/tree` 拉取，子目录直接用树里带的 children（面板一次性返回整棵树）。
struct ScriptBrowserView: View {
    @EnvironmentObject private var session: SessionStore

    /// nil 表示这是根目录，需要联网加载；子目录直接传 children。
    let nodes: [ScriptNode]?
    let title: String

    @State private var loaded: [ScriptNode] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var keyword = ""

    init(nodes: [ScriptNode]? = nil, title: String = "脚本文件") {
        self.nodes = nodes
        self.title = title
    }

    private var isRoot: Bool { nodes == nil }

    private var displayNodes: [ScriptNode] { nodes ?? loaded }

    private var filtered: [ScriptNode] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = displayNodes
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
            if isLoading && displayNodes.isEmpty {
                VStack {
                    LoadingHint(text: "读取脚本目录…")
                    Spacer()
                }
            } else if let errorText, displayNodes.isEmpty {
                VStack(spacing: 12) {
                    ErrorBanner(text: errorText)
                    Button("重试") { Task { await load() } }
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16)
            } else if filtered.isEmpty {
                VStack {
                    EmptyStateView(icon: "folder",
                                   title: "这里没有文件",
                                   message: keyword.isEmpty ? "面板脚本目录是空的" : "换个关键字试试")
                    Spacer()
                }
            } else {
                List {
                    ForEach(filtered) { node in
                        if node.isDirectory {
                            NavigationLink(destination: ScriptBrowserView(nodes: node.children ?? [], title: node.displayName)) {
                                ScriptNodeRow(node: node)
                            }
                        } else {
                            NavigationLink(destination: ScriptEditorView(path: node.path ?? "", name: node.displayName)) {
                                ScriptNodeRow(node: node)
                            }
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
        .task {
            if isRoot && loaded.isEmpty { await load() }
        }
    }

    private func load() async {
        guard isRoot else { return }
        guard let client = session.client else { return }
        isLoading = true
        errorText = nil
        do {
            loaded = try await client.fetchScriptTree()
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isLoading = false
    }
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
