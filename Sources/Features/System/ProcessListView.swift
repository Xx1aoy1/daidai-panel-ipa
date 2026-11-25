import SwiftUI

@MainActor
final class ProcessListViewModel: ObservableObject {
    @Published var items: [PanelProcess] = []
    @Published var supported = true
    @Published var allSupported = false
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var killingPID: Int?
    @Published var scope: ProcessScope = .task

    func load(client: APIClient) async {
        if items.isEmpty { isLoading = true }
        errorText = nil
        do {
            let payload = try await client.fetchProcesses(scope: scope)
            supported = payload.supported ?? true
            allSupported = payload.allSupported ?? false
            // 面板说「全部进程」不可用时，别把开关留在 all 上，退回任务进程。
            if scope == .all, !allSupported {
                scope = .task
                let retry = try await client.fetchProcesses(scope: .task)
                items = retry.items
            } else {
                items = payload.items
            }
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func kill(_ target: PanelProcess, client: APIClient) async -> String? {
        guard let ticks = target.startTicks else { return "这条记录没带 start_ticks，刷新后再试" }
        killingPID = target.pid
        defer { killingPID = nil }
        do {
            let result = try await client.killProcess(pid: target.pid, startTicks: ticks)
            await load(client: client)
            return result.message ?? "进程已结束"
        } catch {
            // 409 = 进程已经不在（或 PID 被复用），刷一下列表让界面跟上。
            await load(client: client)
            return (error as? PanelError)?.message ?? error.localizedDescription
        }
    }
}

/// 后台进程：看任务拉起的常驻进程，必要时结束它们。
/// 面板只给管理员开放，而且 Magisk 模块版不支持「全部进程」。
struct ProcessListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = ProcessListViewModel()
    @State private var pendingKill: PanelProcess?
    @State private var toast: String?

    var body: some View {
        Group {
            if model.isLoading && model.items.isEmpty {
                VStack {
                    LoadingHint(text: "读取进程…")
                    Spacer()
                }
            } else if let errorText = model.errorText, model.items.isEmpty {
                VStack(spacing: 12) {
                    ErrorBanner(text: errorText)
                    Button("重试") { Task { await load() } }
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16)
            } else if !model.supported {
                VStack {
                    EmptyStateView(icon: "desktopcomputer",
                                   title: "当前面板不支持",
                                   message: "后台进程依赖 Linux 的 /proc，面板跑在非 Linux 系统上时读不到。")
                    Spacer()
                }
            } else {
                List {
                    if model.allSupported {
                        Section {
                            Picker("范围", selection: $model.scope) {
                                ForEach(ProcessScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .onChange(of: model.scope) { _ in
                                Task { await load() }
                            }
                        }
                    }

                    if let errorText = model.errorText {
                        Section { ErrorBanner(text: errorText) }
                    }

                    if model.items.isEmpty {
                        EmptyStateView(icon: "checkmark.seal",
                                       title: "没有常驻进程",
                                       message: model.scope == .task
                                           ? "任务都跑完就退出了，没有留下后台进程。"
                                           : "系统里没有能列出来的进程。")
                            .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(model.items) { item in
                                row(item)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingKill = item
                                        } label: {
                                            Label("结束", systemImage: "xmark.octagon")
                                        }
                                    }
                            }
                        } footer: {
                            Text(footerText)
                                .font(.system(size: 11))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("后台进程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
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
                    .padding(.bottom, 24)
            }
        }
        .confirmationDialog(killTitle,
                            isPresented: Binding(get: { pendingKill != nil },
                                                 set: { if !$0 { pendingKill = nil } }),
                            titleVisibility: .visible) {
            Button("结束进程", role: .destructive) {
                if let target = pendingKill {
                    Task { await kill(target) }
                }
                pendingKill = nil
            }
            Button("取消", role: .cancel) { pendingKill = nil }
        }
        .task { await load() }
    }

    private var footerText: String {
        if model.scope == .task {
            return "只列任务拉起、还没退出的进程（含脱离任务组后继续跑的子孙进程）。结束进程会先发 TERM，等不到退出再发 KILL。"
        }
        return "「全部进程」包含面板与容器的系统进程。面板自身、PID 1、与面板同一进程组的进程面板会直接拒绝，不会让你把面板搞挂。"
    }

    private var killTitle: String {
        guard let target = pendingKill else { return "" }
        let task = target.taskText.map { "（任务：\($0)）" } ?? ""
        return "结束 PID \(target.pid)\(task)？强行结束可能让正在跑的任务留下半截数据。"
    }

    private func row(_ item: PanelProcess) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("PID \(item.pid)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.accent)

                StatusBadge(text: item.stateText, color: stateTint(item), compact: true)

                if model.killingPID == item.pid {
                    ProgressView().scaleEffect(0.6)
                }

                Spacer(minLength: 0)

                Text(item.rssText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text(item.displayCommand)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                if let task = item.taskText {
                    Text(task)
                        .lineLimit(1)
                } else {
                    Text("非任务进程")
                }
                Text("· 已运行 \(item.runtimeText)")
                Text("· \(item.startedText) 启动")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func stateTint(_ item: PanelProcess) -> Color {
        switch (item.state ?? "").lowercased() {
        case "running_with_task": return AppTheme.success
        case "detached": return AppTheme.warning
        default: return AppTheme.idle
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }

    private func kill(_ target: PanelProcess) async {
        guard let client = session.client else { return }
        if let message = await model.kill(target, client: client) {
            flash(message)
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}
