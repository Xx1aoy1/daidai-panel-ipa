import SwiftUI
import UIKit

/// 已装包清单：面板托管的依赖导出、pip 实际装了什么、npm 全局装了什么。
///
/// 三份数据来源不同：
///   - 托管：`GET /deps/export`（text/plain，一行一个，Python 那份就是 requirements.txt）
///   - pip：`GET /deps/pip`（当前 Python 版本的 pip list --format=json）
///   - npm：`GET /deps/npm`（npm list -g --depth=0）
/// 前两份是「面板记录」，第三份是「实际环境」，对不上时以实际环境为准。
struct DependencyInventoryView: View {
    @EnvironmentObject private var session: SessionStore

    private enum Segment: String, CaseIterable, Identifiable {
        case managed = "托管清单"
        case pip = "pip"
        case npm = "npm"

        var id: String { rawValue }
    }

    @State private var segment: Segment = .managed
    @State private var keyword = ""

    // 托管清单
    @State private var exportType = "nodejs"
    @State private var exportPythonVersion = ""
    @State private var exportText = ""

    // pip / npm
    @State private var pipPackages: [PipPackage] = []
    @State private var npmPackages: [NpmPackage] = []
    @State private var runtimes: [PythonRuntime] = []
    @State private var pipVersion = ""

    @State private var isLoading = false
    @State private var isSharing = false
    @State private var errorText: String?
    @State private var toast: String?

    private var filteredPip: [PipPackage] {
        guard !keyword.isEmpty else { return pipPackages }
        return pipPackages.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    private var filteredNpm: [NpmPackage] {
        guard !keyword.isEmpty else { return npmPackages }
        return npmPackages.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("视图", selection: $segment) {
                ForEach(Segment.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .onChange(of: segment) { _ in
                keyword = ""
                Task { await loadCurrent() }
            }

            List {
                if let errorText {
                    Section {
                        ErrorBanner(text: errorText)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }

                switch segment {
                case .managed: managedSection
                case .pip: pipSection
                case .npm: npmSection
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await loadCurrent() }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("已装包清单")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: "按包名搜索")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = currentText
                        flash("已复制到剪贴板")
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .disabled(currentText.isEmpty)
                    Button {
                        isSharing = true
                    } label: {
                        Label("分享 / 存到文件", systemImage: "square.and.arrow.up")
                    }
                    .disabled(currentText.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [currentText])
        }
        .task { await loadCurrent() }
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

    // MARK: - 三个分支

    @ViewBuilder
    private var managedSection: some View {
        Section {
            Picker("类型", selection: $exportType) {
                Text("Node.js").tag("nodejs")
                Text("Python").tag("python")
                Text("系统包").tag("linux")
            }
            .pickerStyle(.segmented)
            .onChange(of: exportType) { _ in
                Task { await loadExport() }
            }

            if exportType == "python" && runtimes.count > 1 {
                Picker("Python 版本", selection: $exportPythonVersion) {
                    ForEach(runtimes) { runtime in
                        Text(runtime.title).tag(runtime.version)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: exportPythonVersion) { _ in
                    Task { await loadExport() }
                }
            }
        } header: {
            Text("导出面板托管的依赖")
        } footer: {
            Text("一行一个包名，按当初填写的原样导出（当初带版本号的才带版本号）。Python 这份直接可以当 requirements.txt 用。")
                .font(.system(size: 11))
        }

        Section {
            if isLoading {
                LoadingHint(text: "生成清单…")
            } else if exportText.isEmpty {
                Text("没有已安装的托管依赖")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text(exportText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("清单 · \(exportText.isEmpty ? 0 : exportText.components(separatedBy: "\n").count) 行")
        }
    }

    @ViewBuilder
    private var pipSection: some View {
        if runtimes.count > 1 {
            Section {
                Picker("Python 版本", selection: $pipVersion) {
                    ForEach(runtimes) { runtime in
                        Text(runtime.title).tag(runtime.version)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: pipVersion) { _ in
                    Task { await loadPip() }
                }
            } footer: {
                Text("切换版本会重新执行该环境下的 pip list。")
                    .font(.system(size: 11))
            }
        }

        Section {
            if isLoading {
                LoadingHint(text: "读取 pip 列表…")
            } else if filteredPip.isEmpty {
                Text(keyword.isEmpty ? "这个环境里没有包" : "没有匹配「\(keyword)」的包")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredPip) { pkg in
                    HStack {
                        Text(pkg.name)
                            .font(.system(size: 13, design: .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(pkg.version ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("pip list · \(pipPackages.count) 个")
        } footer: {
            Text("这是 Python 解释器里实际装着的包，和「托管清单」可能对不上（手动 pip install 的不会进托管记录）。")
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var npmSection: some View {
        Section {
            if isLoading {
                LoadingHint(text: "读取 npm 列表…")
            } else if filteredNpm.isEmpty {
                Text(keyword.isEmpty ? "没有全局安装的 npm 包" : "没有匹配「\(keyword)」的包")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredNpm) { pkg in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pkg.name)
                                .font(.system(size: 13, design: .monospaced))
                                .lineLimit(1)
                            if pkg.overridden {
                                Text("已被托管覆盖")
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.warning)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(pkg.version ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("npm list -g · \(npmPackages.count) 个")
        } footer: {
            Text("npm 的全局目录里实际装着的包（depth=0）。面板自己装的 npm / corepack 也会出现在这里。")
                .font(.system(size: 11))
        }
    }

    // MARK: - 数据

    private var currentText: String {
        switch segment {
        case .managed: return exportText
        case .pip:
            return filteredPip.map { "\($0.name)\($0.version.map { "==\($0)" } ?? "")" }.joined(separator: "\n")
        case .npm:
            return filteredNpm.map { "\($0.name)@\($0.version ?? "")" }.joined(separator: "\n")
        }
    }

    private func loadCurrent() async {
        guard let client = session.client else { return }
        errorText = nil
        switch segment {
        case .managed:
            await loadRuntimesIfNeeded(client: client)
            await loadExport()
        case .pip:
            await loadRuntimesIfNeeded(client: client)
            await loadPip()
        case .npm:
            await loadNpm()
        }
    }

    private func loadRuntimesIfNeeded(client: APIClient) async {
        guard runtimes.isEmpty else { return }
        if let payload = try? await client.fetchPythonRuntimes() {
            runtimes = payload.data
            if pipVersion.isEmpty {
                pipVersion = payload.defaultVersion
                    ?? runtimes.first(where: { $0.isDefault == true })?.version
                    ?? runtimes.first?.version
                    ?? ""
            }
            if exportPythonVersion.isEmpty {
                exportPythonVersion = pipVersion
            }
        }
    }

    private func loadExport() async {
        guard let client = session.client else { return }
        isLoading = true
        do {
            exportText = try await client.exportDependencies(
                type: exportType,
                pythonVersion: exportType == "python" ? exportPythonVersion : nil)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    private func loadPip() async {
        guard let client = session.client else { return }
        isLoading = true
        do {
            let items = try await client.fetchPipPackages(pythonVersion: pipVersion.isEmpty ? nil : pipVersion)
            pipPackages = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    private func loadNpm() async {
        guard let client = session.client else { return }
        isLoading = true
        do {
            npmPackages = try await client.fetchNpmPackages()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}
