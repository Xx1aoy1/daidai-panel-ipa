import SwiftUI

@MainActor
final class SystemInfoViewModel: ObservableObject {
    @Published var info: PanelSystemInfo?
    @Published var health: HealthCheckResult?
    @Published var isLoading = false
    @Published var isChecking = false
    @Published var errorText: String?
    @Published var lastUpdated: Date?

    func load(client: APIClient, silent: Bool = false) async {
        if !silent && info == nil { isLoading = true }
        errorText = nil
        do {
            async let infoTask = client.fetchSystemInfo()
            async let healthTask = client.fetchHealthCheck()
            let (loadedInfo, loadedHealth) = try await (infoTask, healthTask)
            info = loadedInfo
            health = loadedHealth
            lastUpdated = Date()
        } catch {
            // 静默刷新失败不覆盖已有数据，只把错误挂出来。
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    /// 主动体检比 GET 慢（会真跑一遍检查），单独一个入口。
    func runHealthCheck(client: APIClient) async {
        isChecking = true
        errorText = nil
        do {
            health = try await client.runHealthCheck()
            lastUpdated = Date()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isChecking = false
    }
}

struct SystemInfoView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SystemInfoViewModel()

    @State private var autoRefresh = true
    // 放 @State 里：View 每次重建都会重跑 body，裸 let 会不停新建 publisher 并重复订阅。
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let errorText = model.errorText {
                    ErrorBanner(text: errorText)
                }

                if model.isLoading && model.info == nil {
                    LoadingHint(text: "读取主机状态…")
                } else if let info = model.info {
                    resourceCard(info)
                    networkCard(info)
                    healthCard
                    systemCard(info)
                } else {
                    EmptyStateView(icon: "server.rack",
                                   title: "读不到主机信息",
                                   message: "这个接口需要管理员权限")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("系统监控")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle("每 5 秒自动刷新", isOn: $autoRefresh)
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("立即刷新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await check() }
                    } label: {
                        Label("重新体检", systemImage: "stethoscope")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await reload() }
        .onReceive(timer) { _ in
            guard autoRefresh else { return }
            Task { await reload(silent: true) }
        }
    }

    // MARK: - 资源

    private func resourceCard(_ info: PanelSystemInfo) -> some View {
        SectionCard("资源占用", systemImage: "cpu") {
            VStack(spacing: 12) {
                ResourceBar(title: "CPU",
                            fraction: info.cpuFraction,
                            detail: String(format: "%.1f%% · %d 核", info.cpuUsage ?? 0, info.numCpu ?? 0),
                            tint: AppTheme.accent)

                ResourceBar(title: "内存",
                            fraction: info.memoryFraction,
                            detail: "\(Bytes.text(info.memoryUsed)) / \(Bytes.text(info.memoryTotal))",
                            tint: info.memoryFraction > 0.9 ? AppTheme.failure : AppTheme.success)

                ResourceBar(title: "磁盘",
                            fraction: info.diskFraction,
                            detail: "\(Bytes.text(info.diskUsed)) / \(Bytes.text(info.diskTotal))",
                            tint: info.diskFraction > 0.9 ? AppTheme.failure : AppTheme.warning)
            }

            if let updated = model.lastUpdated {
                Text("更新于 \(DateText.clock(updated))\(autoRefresh ? " · 每 5 秒自动刷新" : "")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - 网络

    private func networkCard(_ info: PanelSystemInfo) -> some View {
        SectionCard("网络", systemImage: "network") {
            HStack(spacing: 0) {
                netColumn(title: "下载",
                          speed: info.netRxSpeed,
                          total: info.netRxBytes,
                          icon: "arrow.down.circle.fill",
                          tint: AppTheme.success)
                Divider().frame(height: 42)
                netColumn(title: "上传",
                          speed: info.netTxSpeed,
                          total: info.netTxBytes,
                          icon: "arrow.up.circle.fill",
                          tint: AppTheme.accent)
            }
        }
    }

    private func netColumn(title: String,
                           speed: Double?,
                           total: Double?,
                           icon: String,
                           tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(Bytes.speed(speed))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("累计 \(Bytes.text(total))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - 健康检查

    private var healthCard: some View {
        SectionCard("健康检查", systemImage: "heart.text.square") {
            if let health = model.health {
                VStack(spacing: 8) {
                    ForEach(health.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(item.isOK ? AppTheme.success : AppTheme.failure)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                if let message = item.message, !message.isEmpty {
                                    Text(message)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if let checked = health.lastCheckedAt {
                        HStack {
                            Text("上次体检 \(DateText.relative(checked))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            if model.isChecking {
                                ProgressView().scaleEffect(0.6)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                Text("暂无体检结果")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 系统信息

    private func systemCard(_ info: PanelSystemInfo) -> some View {
        SectionCard("面板与主机", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 7) {
                KeyValueRow(label: "主机名", value: info.hostname ?? "—", monospaced: true)
                KeyValueRow(label: "面板版本", value: info.version ?? "—")
                KeyValueRow(label: "部署方式", value: info.deploymentText)
                KeyValueRow(label: "系统", value: "\(info.os ?? "—") / \(info.arch ?? "—")")
                KeyValueRow(label: "运行时长", value: info.uptime ?? "—")
                KeyValueRow(label: "Go", value: info.goVersion ?? "—", monospaced: true)
                KeyValueRow(label: "协程", value: info.goroutines.map { "\($0)" } ?? "—")
                KeyValueRow(label: "数据目录", value: info.dataDir ?? "—", monospaced: true)
                KeyValueRow(label: "机器码", value: info.machineCode ?? "—", monospaced: true)
            }
        }
    }

    // MARK: - 动作

    private func reload(silent: Bool = false) async {
        guard let client = session.client else { return }
        await model.load(client: client, silent: silent)
    }

    private func check() async {
        guard let client = session.client else { return }
        await model.runHealthCheck(client: client)
    }
}

/// 一条资源占用条：标题 + 百分比 + 进度 + 细节。
private struct ResourceBar: View {
    let title: String
    let fraction: Double
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(tint)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 4 : 0))
                }
            }
            .frame(height: 7)

            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

/// 字节数格式化：面板给的是裸字节，直接显示 1234567890 没法读。
enum Bytes {
    static func text(_ value: Double?) -> String {
        guard let value, value > 0 else { return "0 B" }
        return format(value)
    }

    static func speed(_ value: Double?) -> String {
        guard let value, value > 0 else { return "0 B/s" }
        return format(value) + "/s"
    }

    private static func format(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var number = value
        var index = 0
        while number >= 1024, index < units.count - 1 {
            number /= 1024
            index += 1
        }
        if index == 0 { return String(format: "%.0f %@", number, units[index]) }
        return String(format: "%.1f %@", number, units[index])
    }
}
