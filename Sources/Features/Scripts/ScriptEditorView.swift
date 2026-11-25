import SwiftUI

struct ScriptEditorView: View {
    @EnvironmentObject private var session: SessionStore

    let path: String
    let name: String

    @State private var content = ""
    @State private var original = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isBinary = false
    @State private var errorText: String?
    @State private var toast: String?
    @State private var isFormatting = false
    @State private var runRequest: RunRequest?
    @State private var showVersions = false

    private var isDirty: Bool { content != original }
    private var canRun: Bool { !isBinary && !isLoading && ScriptLanguage.canRun(path: path) }
    private var canFormat: Bool { !isBinary && !isLoading && ScriptLanguage.formatterLanguage(path: path) != nil }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                LoadingHint(text: "读取文件…")
                Spacer()
            } else if isBinary {
                VStack {
                    EmptyStateView(icon: "photo",
                                   title: "二进制文件",
                                   message: "图片或 .so 等二进制文件不支持在 App 内编辑")
                    Spacer()
                }
            } else {
                TextEditor(text: $content)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            if let errorText {
                ErrorBanner(text: errorText)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // 历史版本对所有文本文件都该能看，所以这里的条件是「能编辑」而不是「能运行」。
                if !isLoading && !isBinary {
                    Menu {
                        if canRun {
                            Button {
                                runInline()
                            } label: {
                                Label(isDirty ? "运行当前内容（未保存）" : "运行", systemImage: "play.fill")
                            }
                            if isDirty {
                                Button {
                                    runSaved()
                                } label: {
                                    Label("运行已保存的版本", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            Divider()
                        }
                        if canFormat {
                            Button {
                                formatCode()
                            } label: {
                                Label(isFormatting ? "格式化中…" : "格式化代码", systemImage: "wand.and.stars")
                            }
                            .disabled(isFormatting)
                        }
                        Button {
                            showVersions = true
                        } label: {
                            Label("历史版本", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text(isDirty ? "保存" : "已保存")
                            .fontWeight(isDirty ? .semibold : .regular)
                            .foregroundColor(isDirty ? AppTheme.accent : .secondary)
                    }
                }
                .disabled(isSaving || !isDirty || isLoading || isBinary)
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
                    .padding(.bottom, 22)
            }
        }
        .sheet(item: $runRequest) { request in
            ScriptRunView(title: request.title, source: request.source)
                .environmentObject(session)
        }
        .sheet(isPresented: $showVersions) {
            ScriptVersionListView(path: path, name: name) {
                // 回滚会把文件内容换掉，编辑器里的旧文本必须跟着刷新，否则一保存又把旧内容写回去了。
                Task { await reloadAfterRollback() }
            }
            .environmentObject(session)
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = session.client else {
            isLoading = false
            return
        }
        isLoading = true
        errorText = nil
        do {
            let result = try await client.fetchScriptContent(path: path)
            isBinary = result.binary ?? false
            content = result.content ?? ""
            original = content
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func save() {
        guard let client = session.client else { return }
        isSaving = true
        errorText = nil
        let snapshot = content
        let target = path

        Task {
            do {
                try await client.saveScriptContent(path: target, content: snapshot)
                original = snapshot
                flash("已保存")
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
            isSaving = false
        }
    }

    /// 版本回滚后重读文件：内容与「原始值」一起刷新，界面回到「已保存」状态。
    private func reloadAfterRollback() async {
        guard let client = session.client else { return }
        do {
            let result = try await client.fetchScriptContent(path: path)
            isBinary = result.binary ?? false
            content = result.content ?? ""
            original = content
            flash("已回滚，内容已刷新")
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
    }

    private func runInline() {
        runRequest = RunRequest(title: "运行预览",
                                source: .inline(path: path, content: content))
    }

    private func runSaved() {
        runRequest = RunRequest(title: "运行已保存版本", source: .saved(path: path))
    }

    /// 面板侧调用 black / shfmt / gofmt 处理，没装工具时原样返回 `formatter: "none"`。
    /// 格式化结果只改编辑器里的内容（会变成「未保存」状态），要落盘还是得按保存。
    private func formatCode() {
        guard let client = session.client,
              let language = ScriptLanguage.formatterLanguage(path: path) else { return }
        isFormatting = true
        errorText = nil
        let snapshot = content

        Task {
            do {
                let result = try await client.formatScript(content: snapshot, language: language)
                if let formatted = result.content, formatted != snapshot {
                    content = formatted
                    flash(result.didFormat ? "已用 \(result.formatter ?? "") 格式化，记得保存" : "内容未变化")
                } else {
                    flash(result.didFormat ? "已经是格式化后的样子" : "面板没装 \(language) 格式化器")
                }
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
            isFormatting = false
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { toast = nil }
        }
    }
}

private struct RunRequest: Identifiable {
    let id = UUID()
    let title: String
    let source: ScriptRunner.Source
}
