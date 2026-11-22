import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var task: PanelTask
    private let onChanged: () -> Void

    @State private var latestLog: TaskLog?
    @State private var logHint: String?
    @State private var isLoadingLog = false
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    init(task: PanelTask, onChanged: @escaping () -> Void = {}) {
        _task = State(initialValue: task)
        self.onChanged = onChanged
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let errorText {
                    ErrorBanner(text: errorText)
                }
                statusCard
                actionCard
                logCard
                infoCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 26)
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(task.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if session.canWrite {
                    Menu {
                        Button {
                            showEdit = true
                        } label: {
                            Label("编辑任务", systemImage: "square.and.pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除任务", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            TaskEditView(task: task) {
                Task { await refreshAll() }
                onChanged()
            }
        }
        .confirmationDialog("删除任务后不可恢复（脚本文件保留）", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除任务", role: .destructive) { deleteTask() }
            Button("取消", role: .cancel) {}
        }
        .task { await loadLatestLog() }
    }

    // MARK: - 卡片

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusBadge(text: task.runState.text, color: statusColor)
                StatusBadge(text: task.isEnabled ? "已启用" : "已禁用",
                            color: task.isEnabled ? AppTheme.success : AppTheme.idle)
                if task.isManualTask {
                    StatusBadge(text: "手动", color: AppTheme.warning)
                }
                Spacer()
                if let pid = task.pid, pid > 0 {
                    Text("PID \(pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("执行命令")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(task.command ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(task.cronText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                Spacer()
                if let lastRunAt = task.lastRunAt {
                    Text("上次 \(DateText.relative(lastRunAt))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .cardStyle()
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            if session.canWrite {
                HStack(spacing: 10) {
                    if task.runState == .running {
                        actionButton(title: "停止运行", icon: "stop.fill", color: AppTheme.failure) {
                            run { client in try await client.stopTask(id: task.id) }
                        }
                    } else {
                        actionButton(title: "立即运行", icon: "play.fill", color: AppTheme.accent) {
                            run { client in try await client.runTask(id: task.id) }
                        }
                    }

                    actionButton(title: task.isEnabled ? "禁用" : "启用",
                                 icon: task.isEnabled ? "pause.fill" : "checkmark.circle.fill",
                                 color: task.isEnabled ? AppTheme.warning : AppTheme.success) {
                        run { client in
                            try await client.setTaskEnabled(id: task.id, enabled: !task.isEnabled)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                NavigationLink(destination: LiveLogView(taskID: task.id, title: task.displayName)) {
                    actionLabel(title: "实时日志", icon: "text.alignleft", color: AppTheme.running)
                }
                .buttonStyle(.plain)

                if session.canWrite {
                    actionButton(title: "编辑", icon: "square.and.pencil", color: AppTheme.idle) {
                        showEdit = true
                    }
                }
            }
        }
        .cardStyle()
    }

    private var logCard: some View {
        SectionCard("最近一次执行", systemImage: "doc.text") {
            if isLoadingLog {
                LoadingHint(text: "读取日志…")
            } else if let latestLog {
                HStack(spacing: 6) {
                    StatusBadge(text: latestLog.statusKind.text, color: logColor(latestLog.statusKind))
                    Text(DateText.relative(latestLog.startedAt ?? latestLog.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("耗时 \(latestLog.durationText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                let preview = Array(latestLog.contentLines.suffix(14)).joined(separator: "\n")
                Text(preview.isEmpty ? "（日志为空）" : preview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                NavigationLink(destination: LogDetailView(logID: latestLog.id, title: task.displayName)) {
                    HStack(spacing: 4) {
                        Text("查看完整日志")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(AppTheme.accent)
                }
            } else {
                Text(logHint ?? "还没有执行记录")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var infoCard: some View {
        SectionCard("任务信息", systemImage: "info.circle") {
            KeyValueRow(label: "任务 ID", value: "\(task.id)")
            Divider()
            KeyValueRow(label: "类型", value: task.isManualTask ? "手动触发" : "Cron 定时")
            Divider()
            KeyValueRow(label: "超时", value: (task.timeout ?? 0) > 0 ? "\(task.timeout ?? 0) 秒" : "不限制")
            Divider()
            KeyValueRow(label: "重试", value: (task.maxRetries ?? 0) > 0 ? "\(task.maxRetries ?? 0) 次" : "不重试")
            Divider()
            KeyValueRow(label: "成功码", value: task.successExitCodes ?? "0")
            Divider()
            KeyValueRow(label: "并发", value: (task.allowMultipleInstances ?? false) ? "允许同时运行" : "单实例")
            if let message = task.lastSkipReason, !message.isEmpty {
                Divider()
                KeyValueRow(label: "上次跳过", value: message, valueColor: AppTheme.warning)
            }
            if let createdAt = DateParser.parse(task.createdAt) {
                Divider()
                KeyValueRow(label: "创建于", value: DateText.total(createdAt))
            }
        }
    }

    // MARK: - 小组件

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func actionLabel(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .foregroundColor(color)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusColor: Color {
        switch task.runState {
        case .running: return AppTheme.running
        case .queued: return AppTheme.warning
        case .idle: return AppTheme.success
        case .disabled: return AppTheme.idle
        case .unknown: return AppTheme.idle
        }
    }

    private func logColor(_ kind: LogStatusKind) -> Color {
        switch kind {
        case .success: return AppTheme.success
        case .failed: return AppTheme.failure
        case .running: return AppTheme.running
        case .aborted: return AppTheme.warning
        case .unknown: return AppTheme.idle
        }
    }

    // MARK: - 行为

    private func loadLatestLog() async {
        guard let client = session.client else { return }
        isLoadingLog = true
        do {
            latestLog = try await client.fetchLatestLog(taskId: task.id)
        } catch let error as PanelError {
            // 面板对「还没跑过」的任务回 404 + {"error":"该任务还没有日志记录"}，这不是错误，是空态。
            if case .server(let status, _, _) = error, status == 404 {
                latestLog = nil
                logHint = "该任务还没有执行记录"
            } else {
                logHint = error.message
            }
        } catch {
            logHint = error.localizedDescription
        }
        isLoadingLog = false
    }

    private func refreshAll() async {
        await refreshTask()
        await loadLatestLog()
    }

    private func refreshTask() async {
        guard let client = session.client else { return }
        do {
            let result = try await client.fetchTasks(keyword: task.name ?? "", pageSize: 100)
            if let updated = result.items.first(where: { $0.id == task.id }) {
                task = updated
            }
        } catch {
            // 刷新失败不影响当前展示
        }
    }

    private func run(_ operation: @escaping (APIClient) async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        errorText = nil
        Task {
            do {
                let client = try session.requireClient()
                try await operation(client)
                try? await Task.sleep(nanoseconds: 350_000_000)
                await refreshAll()
                onChanged()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
            isBusy = false
        }
    }

    private func deleteTask() {
        Task {
            do {
                let client = try session.requireClient()
                try await client.deleteTask(id: task.id)
                onChanged()
                presentationMode.wrappedValue.dismiss()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
        }
    }
}
