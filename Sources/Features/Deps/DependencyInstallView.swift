import SwiftUI

/// 新建依赖：一次可以提交多个包名（换行、逗号、空格都认）。
struct DependencyInstallView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var type = "nodejs"
    @State private var text = ""
    @State private var pythonVersion = ""
    @State private var runtimes: [PythonRuntime] = []
    @State private var isSubmitting = false
    @State private var errorText: String?

    let onDone: (String) -> Void

    private let types: [(key: String, label: String)] = [
        ("nodejs", "Node.js"),
        ("python", "Python"),
        ("linux", "系统包")
    ]
    /// 面板会静默丢弃含这些字符的包名（防命令注入），本地先挑出来提示。
    private var invalidNames: [String] {
        names.filter { name in
            name.hasPrefix("-") || name.rangeOfCharacter(from: CharacterSet(charactersIn: ";|&`$(){}")) != nil
        }
    }

    private var names: [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: CharacterSet(charactersIn: ",，;； \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private var validNames: [String] {
        let bad = Set(invalidNames)
        return names.filter { !bad.contains($0) }
    }

    var body: some View {
        Form {
            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                Picker("类型", selection: $type) {
                    ForEach(types.indices, id: \.self) { index in
                        Text(types[index].label).tag(types[index].key)
                    }
                }
                .pickerStyle(.segmented)

                if type == "python" {
                    Picker("Python 版本", selection: $pythonVersion) {
                        Text(defaultRuntimeLabel).tag("")
                        ForEach(runtimes) { runtime in
                            Text(runtime.title).tag(runtime.version)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("安装到")
            } footer: {
                Text(typeHint)
                    .font(.system(size: 11))
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("一行一个包名，例如：\nrequests\nhttpx[http2]==0.28.1")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 120)
                }
            } header: {
                Text("包名")
            } footer: {
                if invalidNames.isEmpty {
                    Text("换行、逗号、空格都当分隔符；同名已安装的会被面板跳过。")
                        .font(.system(size: 11))
                } else {
                    Text("这些名字会被面板丢弃（含 ; | & $ ( ) { } 或以 - 开头）：\(invalidNames.joined(separator: "、"))")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.failure)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text(isSubmitting ? "提交中…" : "开始安装（\(validNames.count) 个）")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                }
                .disabled(validNames.isEmpty || isSubmitting || !session.canWrite)
            } footer: {
                Text("提交后安装是异步跑的，可以退出这一页；回到列表能看到「安装中」，点进去有实时日志。")
                    .font(.system(size: 11))
            }
        }
        .navigationTitle("新建依赖")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { await loadRuntimes() }
    }

    private var defaultRuntimeLabel: String {
        guard let version = runtimes.first(where: { $0.isDefault == true })?.version,
              !version.isEmpty
        else { return "使用面板默认版本" }
        return "使用默认（Python \(version)）"
    }

    private var typeHint: String {
        switch type {
        case "python": return "Python 包走 pip，按选中的版本装进对应 venv；不选则用面板的默认版本。"
        case "linux": return "系统包走 apt-get，装进容器/宿主机，需要 root 权限。"
        default: return "Node.js 包走 npm，装到全局（npm install -g）。"
        }
    }

    private func loadRuntimes() async {
        guard let client = session.client else { return }
        if let payload = try? await client.fetchPythonRuntimes() {
            runtimes = payload.data
        }
    }

    private func submit() async {
        guard let client = session.client else { return }
        isSubmitting = true
        errorText = nil
        do {
            let result = try await client.installDependencies(type: type,
                                                             names: validNames,
                                                             pythonVersion: type == "python" ? pythonVersion : nil)
            isSubmitting = false
            onDone(result.message ?? "已提交安装")
            dismiss()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            isSubmitting = false
        }
    }
}
