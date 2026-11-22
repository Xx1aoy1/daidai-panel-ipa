import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var dashboard: PanelDashboard?
    @Published var panelVersion: String?
    @Published var isLoading = false
    @Published var errorText: String?

    func load(client: APIClient, session: SessionStore) async {
        if dashboard == nil { isLoading = true }
        errorText = nil
        do {
            dashboard = try await client.fetchDashboard(range: 7)
            if panelVersion == nil, let info = try? await client.panelVersion() {
                panelVersion = info.version
            }
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isLoading = false
    }
}

struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = DashboardViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    if let errorText = model.errorText {
                        ErrorBanner(text: errorText)
                    }
                    serverCard
                    if model.isLoading && model.dashboard == nil {
                        LoadingHint(text: "正在读取面板数据…")
                    } else if let data = model.dashboard {
                        overviewTiles(data)
                        todayCard(data)
                        trendCard(data)
                        resourceTiles(data)
                        recentCard(data)
                    } else {
                        EmptyStateView(icon: "gauge",
                                       title: "暂无数据",
                                       message: "下拉或点右上角刷新试试")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("概览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await refresh() }
    }

    // MARK: - 卡片

    private var serverCard: some View {
        HStack(spacing: 12) {
            AppLogo(size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.currentServer?.displayName ?? "未连接")
                    .font(.system(size: 15, weight: .semibold))
                Text(session.currentServer?.baseURL ?? "—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let panelVersion = model.panelVersion {
                    StatusBadge(text: "v\(panelVersion)", color: AppTheme.accent)
                }
                Text(session.user?.roleText ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }

    private func overviewTiles(_ data: PanelDashboard) -> some View {
        HStack(spacing: 10) {
            StatTile(title: "运行中",
                     value: "\(data.runningTasks ?? 0)",
                     subtitle: "启用 \(data.enabledTasks ?? 0) / 共 \(data.taskCount ?? 0)",
                     tint: AppTheme.running,
                     systemImage: "bolt.fill")
            StatTile(title: "今日执行",
                     value: "\(data.todayLogs ?? 0)",
                     subtitle: "昨日 \(data.yesterdayLogs ?? 0)",
                     tint: AppTheme.accent,
                     systemImage: "clock.arrow.circlepath")
            StatTile(title: "成功率",
                     value: data.successRateText,
                     subtitle: "成功 \(data.successLogs ?? 0)",
                     tint: AppTheme.success,
                     systemImage: "checkmark.seal.fill")
        }
    }

    private func todayCard(_ data: PanelDashboard) -> some View {
        SectionCard("今日执行明细", systemImage: "chart.bar.fill") {
            HStack(spacing: 10) {
                miniCount(title: "成功", value: data.successLogs ?? 0, color: AppTheme.success)
                miniCount(title: "失败", value: data.failedLogs ?? 0, color: AppTheme.failure)
                miniCount(title: "中断", value: data.abortedLogs ?? 0, color: AppTheme.warning)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(AppTheme.success)
                        .frame(width: max(0, geometry.size.width * CGFloat(data.successRate)))
                }
            }
            .frame(height: 7)
            .padding(.top, 2)

            Text("昨日同期：成功 \(data.yesterdaySuccess ?? 0) · 失败 \(data.yesterdayFailed ?? 0) · 中断 \(data.yesterdayAborted ?? 0)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func miniCount(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendCard(_ data: PanelDashboard) -> some View {
        SectionCard("近 7 日趋势", systemImage: "chart.line.uptrend.xyaxis") {
            if let stats = data.dailyStats, !stats.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(stats) { stat in
                        trendBar(stat, maxTotal: data.maxDailyTotal)
                    }
                }
                .frame(height: 96)
                HStack(spacing: 12) {
                    legend(color: AppTheme.success, text: "成功")
                    legend(color: AppTheme.failure, text: "失败")
                    legend(color: AppTheme.warning, text: "中断")
                    Spacer()
                }
            } else {
                Text("暂无趋势数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func trendBar(_ stat: DailyStat, maxTotal: Int) -> some View {
        let maxValue = CGFloat(max(maxTotal, 1))
        let total = stat.total
        let height = total > 0 ? max(6, 80 * CGFloat(total) / maxValue) : 4
        let successH = total > 0 ? height * CGFloat(stat.success ?? 0) / CGFloat(total) : 0
        let failedH = total > 0 ? height * CGFloat(stat.failed ?? 0) / CGFloat(total) : 0
        let abortedH = total > 0 ? height * CGFloat(stat.aborted ?? 0) / CGFloat(total) : 0

        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if total == 0 {
                    Rectangle().fill(Color.secondary.opacity(0.16)).frame(height: 4)
                } else {
                    Rectangle().fill(AppTheme.warning).frame(height: abortedH)
                    Rectangle().fill(AppTheme.failure).frame(height: failedH)
                    Rectangle().fill(AppTheme.success).frame(height: successH)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            Text(stat.shortDate)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func resourceTiles(_ data: PanelDashboard) -> some View {
        HStack(spacing: 10) {
            StatTile(title: "环境变量",
                     value: "\(data.envCount ?? 0)",
                     subtitle: "条",
                     tint: AppTheme.accent,
                     systemImage: "key.fill")
            StatTile(title: "订阅",
                     value: "\(data.subCount ?? 0)",
                     subtitle: "个",
                     tint: AppTheme.warning,
                     systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func recentCard(_ data: PanelDashboard) -> some View {
        SectionCard("最近执行", systemImage: "clock.fill") {
            let logs = data.recentLogs ?? []
            if logs.isEmpty {
                Text("还没有执行记录")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(logs.prefix(6).enumerated()), id: \.element.id) { index, log in
                        NavigationLink(destination: LogDetailView(logID: log.id, title: log.titleText)) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(color(for: log.statusKind))
                                    .frame(width: 7, height: 7)
                                Text(log.titleText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(DateText.relative(log.startedAt ?? log.createdAt))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)

                        if index < min(logs.count, 6) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func color(for kind: LogStatusKind) -> Color {
        switch kind {
        case .success: return AppTheme.success
        case .failed: return AppTheme.failure
        case .running: return AppTheme.running
        case .aborted: return AppTheme.warning
        case .unknown: return AppTheme.idle
        }
    }

    private func refresh() async {
        do {
            let client = try session.requireClient()
            await model.load(client: client, session: session)
        } catch {
            model.errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }
}
