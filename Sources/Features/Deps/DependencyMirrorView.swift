import SwiftUI

/// 依赖镜像源：pip / npm / 系统包。
///
/// 面板用「指针判空」判断要不要改：请求里不带的字段保持原值。所以这里只提交改动过的字段，
/// 避免把没动的镜像又写一遍（写 npm 镜像会顺手跑一次 npm 配置，没必要）。
struct DependencyMirrorView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var mirrors: DepMirrors?
    @State private var pip = ""
    @State private var npm = ""
    @State private var linux = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var toast: String?

    private let pipPresets: [(String, String)] = [
        ("腾讯云", "https://mirrors.cloud.tencent.com/pypi/simple"),
        ("阿里云", "https://mirrors.aliyun.com/pypi/simple/"),
        ("清华大学", "https://pypi.tuna.tsinghua.edu.cn/simple"),
        ("官方 PyPI", "https://pypi.org/simple")
    ]

    private let npmPresets: [(String, String)] = [
        ("npmmirror", "https://registry.npmmirror.com/"),
        ("官方 npm", "https://registry.npmjs.org/")
    ]

    private let linuxPresets: [(String, String)] = [
        ("阿里云", "https://mirrors.aliyun.com/debian"),
        ("清华大学", "https://mirrors.tuna.tsinghua.edu.cn/debian"),
        ("腾讯云", "https://mirrors.cloud.tencent.com/debian"),
        ("官方源", "http://deb.debian.org/debian")
    ]

    private var hasChanges: Bool {
        guard let mirrors else { return false }
        return pip != (mirrors.pipMirror ?? "")
            || npm != (mirrors.npmMirror ?? "")
            || linux != (mirrors.linuxMirror ?? "")
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

            if isLoading && mirrors == nil {
                Section { LoadingHint(text: "读取镜像配置…") }
            } else if let mirrors {
                Section {
                    field(title: "pip 镜像", text: $pip, presets: pipPresets, placeholder: "https://…/simple")
                } header: {
                    Text("Python")
                } footer: {
                    Text("装 Python 依赖时传给 pip 的 index-url。留空表示使用 pip 默认源。")
                        .font(.system(size: 11))
                }

                Section {
                    field(title: "npm 镜像", text: $npm, presets: npmPresets, placeholder: "https://registry.npmjs.org/")
                } header: {
                    Text("Node.js")
                } footer: {
                    Text("装 Node.js 依赖时用的 registry。")
                        .font(.system(size: 11))
                }

                Section {
                    field(title: "系统包镜像",
                          text: $linux,
                          presets: linuxPresets,
                          placeholder: mirrors.linuxMirrorSupported == false ? "当前环境不支持" : "https://…/debian")
                        .disabled(mirrors.linuxMirrorSupported == false)

                    KeyValueRow(label: "包管理器", value: mirrors.packageManagerText, monospaced: true)
                } header: {
                    Text(mirrors.linuxMirrorLabel ?? "系统包")
                } footer: {
                    if let message = mirrors.linuxMirrorMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.warning)
                    } else {
                        Text("换源会重写 apt 的 sources.list；换到慢源后第一次 apt 操作会明显变慢。非 Debian 系（如 Alpine）不支持。")
                            .font(.system(size: 11))
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView().scaleEffect(0.8) }
                            Text(isSaving ? "保存中…" : "保存镜像源")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                } footer: {
                    Text("只提交改动过的项，没动的镜像不会被重写。")
                        .font(.system(size: 11))
                }
            } else {
                Section {
                    EmptyStateView(icon: "network",
                                   title: "读不到镜像配置",
                                   message: errorText == nil ? "需要管理员权限" : nil)
                }
            }
        }
        .navigationTitle("镜像源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
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
    }

    private func field(title: String,
                       text: Binding<String>,
                       presets: [(String, String)],
                       placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Menu {
                    ForEach(presets.indices, id: \.self) { index in
                        Button(presets[index].0) { text.wrappedValue = presets[index].1 }
                    }
                    Button("清空") { text.wrappedValue = "" }
                } label: {
                    Text("常用")
                        .font(.system(size: 12))
                }
            }
            TextField(placeholder, text: text)
                .font(.system(size: 12, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        isLoading = true
        errorText = nil
        do {
            let loaded = try await client.fetchDepMirrors()
            mirrors = loaded
            pip = loaded.pipMirror ?? ""
            npm = loaded.npmMirror ?? ""
            linux = loaded.linuxMirror ?? ""
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        guard let client = session.client, let mirrors else { return }
        isSaving = true
        errorText = nil
        do {
            let changedPip: String? = pip == (mirrors.pipMirror ?? "") ? nil : pip
            let changedNpm: String? = npm == (mirrors.npmMirror ?? "") ? nil : npm
            let changedLinux: String? = linux == (mirrors.linuxMirror ?? "") ? nil : linux
            let message = try await client.setDepMirrors(pip: changedPip,
                                                         npm: changedNpm,
                                                         linux: changedLinux)
            flash(message ?? "镜像源已保存")
            await load()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isSaving = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}
