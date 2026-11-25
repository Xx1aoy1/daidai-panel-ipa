import SwiftUI
import UIKit

/// 脚本历史版本：预览 / 回滚 / 清空。
///
/// 面板每次保存都会记一版，回滚不是「删掉新版本」，而是把旧内容写回文件、
/// 再追加一条「回滚到 vN」的新版本 —— 所以回滚本身也能再滚回去。
struct ScriptVersionListView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.presentationMode) private var presentationMode

    let path: String
    let name: String
    /// 回滚成功后回调，让上层编辑器重新读一次文件内容。
    var onRolledBack: (() -> Void)? = nil

    @State private var versions: [ScriptVersion] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var pendingConfirm: VersionConfirm?
    @State private var toast: String?
    @State private var isWorking = false

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack {
                        LoadingHint(text: "读取版本…")
                        Spacer()
                    }
                } else if let errorText, versions.isEmpty {
                    VStack(spacing: 12) {
                        ErrorBanner(text: errorText)
                        Button("重试") { Task { await load() } }
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(16)
                } else if versions.isEmpty {
                    VStack {
                        EmptyStateView(icon: "clock",
                                       title: "还没有历史版本",
                                       message: "面板在每次保存时才会生成一个版本")
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            ForEach(versions) { item in
                                NavigationLink(destination: ScriptVersionDetailView(versionID: item.id,
                                                                                    title: "\(name) · \(item.versionText)")) {
                                    row(item)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        pendingConfirm = .rollback(item)
                                    } label: {
                                        Label("回滚", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(AppTheme.warning)
                                }
                            }
                        } footer: {
                            Text("共 \(versions.count) 个版本（面板最多保留 50 个）。左滑可回滚；回滚会写回文件并新增一条「回滚到 vN」记录。")
                                .font(.system(size: 11))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("历史版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isWorking {
                        ProgressView().scaleEffect(0.8)
                    } else if !versions.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                pendingConfirm = .clearAll
                            } label: {
                                Label("清空历史版本", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
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
            .confirmationDialog(confirmTitle,
                                isPresented: Binding(get: { pendingConfirm != nil },
                                                     set: { if !$0 { pendingConfirm = nil } }),
                                titleVisibility: .visible) {
                if let pending = pendingConfirm {
                    switch pending {
                    case .rollback(let target):
                        Button("回滚到 \(target.versionText)", role: .destructive) {
                            pendingConfirm = nil
                            Task { await rollback(target) }
                        }
                    case .clearAll:
                        Button("清空 \(versions.count) 个版本", role: .destructive) {
                            pendingConfirm = nil
                            Task { await clearAll() }
                        }
                    }
                }
                Button("取消", role: .cancel) { pendingConfirm = nil }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private var confirmTitle: String {
        guard let pending = pendingConfirm else { return "" }
        switch pending {
        case .rollback(let target):
            let time = DateParser.parse(target.createdAt).map(DateText.absolute) ?? "—"
            return "把「\(name)」回滚到 \(target.versionText)（\(time)）？当前内容会被覆盖，但会作为新版本保留下来。"
        case .clearAll:
            return "清空后这些版本全部消失，当前文件内容不变，但再也回不去了。"
        }
    }

    private func row(_ item: ScriptVersion) -> some View {
        HStack(spacing: 10) {
            Text(item.versionText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.accent)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text((item.message?.isEmpty == false) ? item.message! : "自动保存")
                    .font(.system(size: 13))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(DateText.absolute(DateParser.parse(item.createdAt) ?? Date()))
                    if let length = item.contentLength, length > 0 {
                        Text("· \(length) 字符")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        guard let client = session.client else {
            isLoading = false
            return
        }
        isLoading = true
        errorText = nil
        do {
            versions = try await client.fetchScriptVersions(path: path)
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func rollback(_ target: ScriptVersion) async {
        guard let client = session.client else { return }
        isWorking = true
        errorText = nil
        do {
            let message = try await client.rollbackScriptVersion(id: target.id)
            await load()
            flash(message ?? "已回滚到 \(target.versionText)")
            onRolledBack?()
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isWorking = false
    }

    private func clearAll() async {
        guard let client = session.client else { return }
        isWorking = true
        errorText = nil
        do {
            let cleared = try await client.clearScriptVersions(path: path)
            versions = []
            flash("已清空 \(cleared ?? 0) 个版本")
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isWorking = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

private enum VersionConfirm: Identifiable {
    case rollback(ScriptVersion)
    case clearAll

    var id: String {
        switch self {
        case .rollback(let version): return "rollback-\(version.id)"
        case .clearAll: return "clearAll"
        }
    }
}

private struct ScriptVersionDetailView: View {
    @EnvironmentObject private var session: SessionStore

    let versionID: Int
    let title: String

    @State private var detail: ScriptVersionDetail?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    LoadingHint(text: "读取内容…")
                    Spacer()
                }
            } else if let errorText, detail == nil {
                VStack(spacing: 12) {
                    ErrorBanner(text: errorText)
                    Spacer()
                }
                .padding(16)
            } else {
                ScrollView {
                    Text((detail?.content?.isEmpty == false) ? detail!.content! : "（该版本内容为空）")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .background(Color(UIColor.systemBackground).ignoresSafeArea())
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = detail?.content ?? ""
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(detail?.content?.isEmpty != false)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = session.client else {
            isLoading = false
            return
        }
        do {
            detail = try await client.fetchScriptVersion(id: versionID)
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isLoading = false
    }
}
