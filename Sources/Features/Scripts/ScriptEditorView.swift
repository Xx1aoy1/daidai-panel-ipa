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
    @State private var runRequest: RunRequest?
    @State private var showVersions = false

    private var isDirty: Bool { content != original }
    private var canRun: Bool { !isBinary && !isLoading && ScriptLanguage.canRun(path: path) }

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
                if canRun {
                    Menu {
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
                        Button {
                            showVersions = true
                        } label: {
                            Label("历史版本", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "play.circle")
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
            ScriptVersionListView(path: path, name: name)
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

    private func runInline() {
        runRequest = RunRequest(title: "运行预览",
                                source: .inline(path: path, content: content))
    }

    private func runSaved() {
        runRequest = RunRequest(title: "运行已保存版本", source: .saved(path: path))
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
