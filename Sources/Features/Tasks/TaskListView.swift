import SwiftUI

enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case running = "运行中"
    case enabled = "已启用"
    case disabled = "已禁用"

    var id: String { rawValue }

    /// 面板 `GET /tasks?status=` 用的是精确匹配的数值：0 禁用 / 1 启用 / 2 运行中。
    var statusParam: String? {
        switch self {
        case .all: return nil
        case .running: return "2"
        case .enabled: return "1"
        case .disabled: return "0"
        }
    }
}

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var tasks: [PanelTask] = []
    @Published var keyword = ""
    @Published var filter: TaskFilter = .all
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorText: String?
    @Published var total = 0

    private var page = 1
    private var hasMore = false

    func reload(client: APIClient) async {
        if tasks.isEmpty { isLoading = true }
        errorText = nil
        do {
            let result = try await client.fetchTasks(keyword: keyword,
                                                    status: filter.statusParam,
                                                    page: 1,
                                                    pageSize: 30)
            tasks = result.items
            total = result.total
            page = 1
            hasMore = result.hasMore
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func loadMore(client: APIClient) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        do {
            let next = page + 1
            let result = try await client.fetchTasks(keyword: keyword,
                                                    status: filter.statusParam,
                                                    page: next,
                                                    pageSize: 30)
            page = next
            total = result.total
            hasMore = result.hasMore
            let existing = Set(tasks.map { $0.id })
            tasks.append(contentsOf: result.items.filter { !existing.contains($0.id) })
        } catch {
            hasMore = false
        }
        isLoadingMore = false
    }
}

struct TaskListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = TaskListViewModel()
    @State private var showCreate = false
    @State private var pendingDelete: PanelTask?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                filterBar
                content
            }
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .navigationTitle("任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if session.canWrite {
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .searchable(text: $model.keyword, prompt: "任务名或命令关键字")
            .onSubmit(of: .search) {
                Task { await reload() }
            }
            .sheet(isPresented: $showCreate) {
                TaskEditView(task: nil) {
                    Task { await reload() }
                }
            }
            .alert(item: $pendingDelete) { task in
                Alert(title: Text("删除任务"),
                      message: Text("确定删除「\(task.displayName)」吗？脚本文件不会被删除。"),
                      primaryButton: .destructive(Text("删除")) {
                        perform { client in
                            try await client.deleteTask(id: task.id)
                        }
                    },
                      secondaryButton: .cancel(Text("取消")))
            }
        }
        .navigationViewStyle(.stack)
        .task { await reload() }
    }

    // MARK: - 子视图

    private var filterBar: some View {
        VStack(spacing: 6) {
            Picker("筛选", selection: $model.filter) {
                ForEach(TaskFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if session.isViewer {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                    Text("当前账号只读（viewer），不能运行或修改任务")
                        .font(.system(size: 11))
                    Spacer()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onChange(of: model.filter) { _ in
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorText = model.errorText, model.tasks.isEmpty {
            VStack(spacing: 12) {
                ErrorBanner(text: errorText)
                Button("重试") { Task { await reload() } }
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(16)
            Spacer()
        } else if model.isLoading && model.tasks.isEmpty {
            LoadingHint(text: "正在加载任务…")
            Spacer()
        } else if model.tasks.isEmpty {
            EmptyStateView(icon: "tray",
                           title: "没有符合条件的任务",
                           message: session.canWrite
                                ? "换个筛选条件，或点右上角 + 新建任务"
                                : "换个筛选条件试试（当前账号只读）")
            Spacer()
        } else {
            List {
                Section {
                    ForEach(model.tasks) { task in
                        NavigationLink(destination: TaskDetailView(task: task) {
                            Task { await reload() }
                        }) {
                            TaskRow(task: task)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if session.canWrite {
                                Button(role: .destructive) {
                                    pendingDelete = task
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                if task.runState == .running {
                                    Button {
                                        perform { client in try await client.stopTask(id: task.id) }
                                    } label: {
                                        Label("停止", systemImage: "stop.fill")
                                    }
                                    .tint(AppTheme.failure)
                                } else {
                                    Button {
                                        perform { client in try await client.runTask(id: task.id) }
                                    } label: {
                                        Label("运行", systemImage: "play.fill")
                                    }
                                    .tint(AppTheme.accent)
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if session.canWrite {
                                Button {
                                    perform { client in
                                        try await client.setTaskEnabled(id: task.id, enabled: !task.isEnabled)
                                    }
                                } label: {
                                    Label(task.isEnabled ? "禁用" : "启用",
                                          systemImage: task.isEnabled ? "pause.circle" : "play.circle")
                                }
                                .tint(task.isEnabled ? AppTheme.warning : AppTheme.success)
                            }
                        }
                        .onAppear {
                            if task.id == model.tasks.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }

                    if model.isLoadingMore {
                        LoadingHint(text: "加载更多…")
                    } else if !model.tasks.isEmpty {
                        Text("共 \(model.total) 个任务")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await reload() }
        }
    }

    // MARK: - 行为

    private func reload() async {
        do {
            let client = try session.requireClient()
            await model.reload(client: client)
        } catch {
            model.errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let client = session.client else { return }
        await model.loadMore(client: client)
    }

    private func perform(_ operation: @escaping (APIClient) async throws -> Void) {
        Task {
            do {
                let client = try session.requireClient()
                try await operation(client)
                await reload()
            } catch {
                if !session.handle(error) {
                    model.errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: PanelTask

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if task.isPinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.warning)
                    }
                    Text(task.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(task.cronText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(text: task.runState.text, color: color, compact: true)
                if let lastRunAt = task.lastRunAt {
                    Text(DateText.relative(lastRunAt))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var color: Color {
        switch task.runState {
        case .running: return AppTheme.running
        case .queued: return AppTheme.warning
        case .idle: return task.isEnabled ? AppTheme.success : AppTheme.idle
        case .disabled: return AppTheme.idle
        case .unknown: return AppTheme.idle
        }
    }
}
