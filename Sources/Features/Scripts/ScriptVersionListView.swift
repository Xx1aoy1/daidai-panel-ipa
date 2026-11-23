import SwiftUI
import UIKit

/// 脚本历史版本。只做「看」，不做回滚 —— 手机上误触回滚的代价太大，需要恢复请用面板网页端。
struct ScriptVersionListView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.presentationMode) private var presentationMode

    let path: String
    let name: String

    @State private var versions: [ScriptVersion] = []
    @State private var isLoading = true
    @State private var errorText: String?

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
                            }
                        } footer: {
                            Text("共 \(versions.count) 个版本。历史版本为只读预览，恢复请在面板网页端操作。")
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
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
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
