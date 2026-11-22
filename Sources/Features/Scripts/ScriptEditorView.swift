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

    private var isDirty: Bool { content != original }

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
            ToolbarItem(placement: .navigationBarTrailing) {
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

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { toast = nil }
        }
    }
}
