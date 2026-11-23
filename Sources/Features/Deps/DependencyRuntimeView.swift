import SwiftUI

@MainActor
final class DependencyRuntimeViewModel: ObservableObject {
    @Published var runtimes: [PythonRuntime] = []
    @Published var defaultVersion: String?
    @Published var playwright: PlaywrightStatus?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isInstalling = false
    @Published var errorText: String?
    @Published var toast: String?

    func load(client: APIClient) async {
        if runtimes.isEmpty { isLoading = true }
        errorText = nil
        do {
            async let runtimeTask = client.fetchPythonRuntimes()
            async let playwrightTask = client.fetchPlaywrightStatus()
            let (payload, pw) = try await (runtimeTask, playwrightTask)
            runtimes = payload.data
            defaultVersion = payload.defaultVersion
            playwright = pw
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func setDefault(_ runtime: PythonRuntime, client: APIClient) async {
        guard defaultVersion != runtime.version else { return }
        isSaving = true
        errorText = nil
        do {
            let message = try await client.setDefaultPythonRuntime(version: runtime.version)
            defaultVersion = runtime.version
            flash(message ?? "默认版本已切换为 \(runtime.title)")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isSaving = false
    }

    func installPlaywright(client: APIClient) async {
        isInstalling = true
        errorText = nil
        do {
            let message = try await client.installPlaywright()
            flash(message ?? "已排入安装队列")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isInstalling = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// 运行时环境：多版本 Python 的默认版本切换 + Playwright 一键安装。
struct DependencyRuntimeView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = DependencyRuntimeViewModel()

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                if model.isLoading && model.runtimes.isEmpty {
                    LoadingHint(text: "读取 Python 运行时…")
                } else if model.runtimes.isEmpty {
                    Text("面板没有可用的托管 Python 环境")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.runtimes) { runtime in
                        runtimeRow(runtime)
                    }
                }
            } header: {
                Text("Python 运行时")
            } footer: {
                Text("这里切换的是 `python_default_version`，和「系统设置 → 任务运行」里的那一项是同一个值。装 Python 依赖时不指定版本，就装进默认版本的 venv。")
                    .font(.system(size: 11))
            }

            if let pw = model.playwright {
                Section {
                    KeyValueRow(label: "支持", value: pw.isSupported ? "是" : "否", valueColor: pw.isSupported ? AppTheme.success : AppTheme.failure)
                    if let reason = pw.reason, !reason.isEmpty, !pw.isSupported {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.failure)
                    }
                    KeyValueRow(label: "平台", value: "\(pw.distribution ?? "—") \(pw.versionId ?? "") / \(pw.arch ?? "—")")
                    KeyValueRow(label: "Python 包",
                               value: (pw.pythonInstalled ?? false) ? "已安装" : "未安装",
                               valueColor: (pw.pythonInstalled ?? false) ? AppTheme.success : .secondary)
                    KeyValueRow(label: "浏览器",
                               value: (pw.browsersInstalled ?? false) ? "已下载" : "未下载",
                               valueColor: (pw.browsersInstalled ?? false) ? AppTheme.success : .secondary)
                    HStack {
                        Text("系统依赖")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(pw.linuxText)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    if let total = pw.linuxTotal, total > 0 {
                        ProgressBar(fraction: pw.linuxFraction,
                                    tint: pw.linuxFraction >= 1 ? AppTheme.success : AppTheme.warning)
                    }
                    if let path = pw.browsersPath, !path.isEmpty {
                        KeyValueRow(label: "浏览器目录", value: path, monospaced: true)
                    }

                    Button {
                        Task { await install() }
                    } label: {
                        HStack {
                            if model.isInstalling { ProgressView().scaleEffect(0.8) }
                            Text(model.isInstalling ? "提交中…" : (pw.isReady ? "重新安装 Playwright 环境" : "一键安装 Playwright 环境"))
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                    }
                    .disabled(!pw.isSupported || model.isInstalling)
                } header: {
                    Text("Playwright")
                } footer: {
                    Text("一键安装会把系统依赖（约 \(model.playwright?.linuxTotal ?? 0) 个 apt 包）和 Chromium 排进依赖队列，在「依赖管理」列表里能看到逐条进度和日志。首次安装通常要几分钟，网络慢时更久。")
                        .font(.system(size: 11))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("运行时环境")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .task { await reload() }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
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

    private func runtimeRow(_ runtime: PythonRuntime) -> some View {
        Button {
            guard let client = session.client else { return }
            Task { await model.setDefault(runtime, client: client) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: runtime.version == model.defaultVersion ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(runtime.version == model.defaultVersion ? AppTheme.success : .secondary)
                    .font(.system(size: 15))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(runtime.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        if !runtime.isHealthy {
                            StatusBadge(text: "环境异常", color: AppTheme.failure, compact: true)
                        }
                    }
                    if let path = runtime.venvPath, !path.isEmpty {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if let message = runtime.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundColor(runtime.isHealthy ? .secondary : AppTheme.failure)
                    }
                }

                Spacer(minLength: 4)

                if model.isSaving && runtime.version == model.defaultVersion {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }

    private func install() async {
        guard let client = session.client else { return }
        await model.installPlaywright(client: client)
        await model.load(client: client)
    }
}

/// 细进度条，运行时页和 Playwright 卡片共用。
struct ProgressBar: View {
    let fraction: Double
    var tint: Color = AppTheme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1),
                                      fraction > 0 ? 4 : 0))
            }
        }
        .frame(height: 6)
    }
}
