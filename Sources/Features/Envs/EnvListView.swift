import SwiftUI

@MainActor
final class EnvListViewModel: ObservableObject {
    @Published var envs: [EnvVar] = []
    @Published var keyword = ""
    @Published var isLoading = false
    @Published var errorText: String?

    var filtered: [EnvVar] {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return envs }
        return envs.filter {
            ($0.name ?? "").lowercased().contains(text)
                || ($0.remarks ?? "").lowercased().contains(text)
                || ($0.group ?? "").lowercased().contains(text)
        }
    }

    func load(client: APIClient) async {
        if envs.isEmpty { isLoading = true }
        errorText = nil
        do {
            envs = try await client.fetchEnvs()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct EnvListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = EnvListViewModel()

    @State private var sheet: EnvSheet?
    @State private var revealed: Set<Int> = []
    @State private var pendingDelete: EnvVar?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let errorText = model.errorText, model.envs.isEmpty {
                VStack(spacing: 12) {
                    ErrorBanner(text: errorText)
                    Button("重试") { Task { await load() } }
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16)
            } else if model.isLoading && model.envs.isEmpty {
                VStack {
                    LoadingHint(text: "加载环境变量…")
                    Spacer()
                }
            } else {
                listView
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("环境变量")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheet = .create
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .create:
                EnvEditView(env: nil) { Task { await load() } }
            case .edit(let env):
                EnvEditView(env: env) { Task { await load() } }
            }
        }
        .alert(item: $pendingDelete) { env in
            Alert(title: Text("删除变量"),
                  message: Text("确定删除「\(env.displayName)」吗？删除后任务将读不到该变量。"),
                  primaryButton: .destructive(Text("删除")) {
                      perform { client in try await client.deleteEnv(id: env.id) }
                  },
                  secondaryButton: .cancel(Text("取消")))
        }
        .task { await load() }
    }

    private var listView: some View {
        List {
            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                }
            }

            Section {
                ForEach(model.filtered) { env in
                    Button {
                        sheet = .edit(env)
                    } label: {
                        EnvRow(env: env, revealed: revealed.contains(env.id)) {
                            if revealed.contains(env.id) {
                                revealed.remove(env.id)
                            } else {
                                revealed.insert(env.id)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = env
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggle(env)
                        } label: {
                            Label(env.isEnabled ? "禁用" : "启用",
                                  systemImage: env.isEnabled ? "pause.circle" : "play.circle")
                        }
                        .tint(env.isEnabled ? AppTheme.warning : AppTheme.success)
                    }
                }
            } footer: {
                Text("共 \(model.envs.count) 个变量，点按可编辑；左滑启用/禁用，右滑删除。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $model.keyword, prompt: "按名称、备注或分组筛选")
        .refreshable { await load() }
    }

    private func toggle(_ env: EnvVar) {
        perform { client in
            try await client.setEnvEnabled(id: env.id, enabled: !env.isEnabled)
        }
    }

    private func load() async {
        do {
            let client = try session.requireClient()
            await model.load(client: client)
        } catch {
            model.errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    private func perform(_ operation: @escaping (APIClient) async throws -> Void) {
        Task {
            do {
                let client = try session.requireClient()
                try await operation(client)
                await load()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
        }
    }
}

private enum EnvSheet: Identifiable {
    case create
    case edit(EnvVar)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let env): return "edit-\(env.id)"
        }
    }
}

private struct EnvRow: View {
    let env: EnvVar
    let revealed: Bool
    let onToggleReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(env.isEnabled ? AppTheme.success : AppTheme.idle)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(env.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if env.important == true {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.warning)
                    }
                    if !(env.group ?? "").isEmpty {
                        StatusBadge(text: env.group ?? "", color: AppTheme.accent, compact: true)
                    }
                }

                HStack(spacing: 6) {
                    Text(displayValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if env.looksSensitive {
                        Button(action: onToggleReveal) {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let remarks = env.remarks, !remarks.isEmpty {
                    Text(remarks)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var displayValue: String {
        let raw = env.value ?? ""
        if raw.isEmpty { return "（空）" }
        if env.looksSensitive && !revealed {
            return String(repeating: "•", count: min(max(raw.count, 6), 18))
        }
        return raw
    }
}
