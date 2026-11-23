import SwiftUI

enum DepFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case nodejs = "Node"
    case python = "Python"
    case linux = "系统包"

    var id: String { rawValue }

    var typeKey: String? {
        switch self {
        case .all: return nil
        case .nodejs: return "nodejs"
        case .python: return "python"
        case .linux: return "linux"
        }
    }
}

@MainActor
final class DependencyListViewModel: ObservableObject {
    @Published private(set) var deps: [PanelDependency] = []
    @Published var filter: DepFilter = .all
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toast: String?
    @Published var busyID: Int?

    var filtered: [PanelDependency] {
        let list = filter.typeKey.map { key in deps.filter { $0.type == key } } ?? deps
        // 正在跑的和失败的排前面：这两个状态最需要人看。
        return list.sorted { lhs, rhs in
            if lhs.isBusy != rhs.isBusy { return lhs.isBusy }
            if lhs.isFailed != rhs.isFailed { return lhs.isFailed }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var hasBusy: Bool { deps.contains { $0.isBusy } }

    func count(for filter: DepFilter) -> Int {
        guard let key = filter.typeKey else { return deps.count }
        return deps.filter { $0.type == key }.count
    }

    func load(client: APIClient, silent: Bool = false) async {
        if !silent && deps.isEmpty { isLoading = true }
        if !silent { errorText = nil }
        do {
            deps = try await client.fetchDependencies()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ dep: PanelDependency, client: APIClient) async {
        busyID = dep.id
        do {
            let message = try await client.deleteDependency(id: dep.id)
            deps.removeAll { $0.id == dep.id }
            flash(message ?? "已提交卸载「\(dep.name)」")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        busyID = nil
    }

    func reinstall(_ dep: PanelDependency, client: APIClient) async {
        busyID = dep.id
        do {
            let message = try await client.reinstallDependency(id: dep.id)
            if let index = deps.firstIndex(where: { $0.id == dep.id }) {
                deps[index].status = "installing"
            }
            flash(message ?? "正在重装「\(dep.name)」")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        busyID = nil
    }

    func cancel(_ dep: PanelDependency, client: APIClient) async {
        busyID = dep.id
        do {
            let message = try await client.cancelDependency(id: dep.id)
            flash(message ?? "已提交取消请求")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        busyID = nil
    }

    func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct DependencyListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = DependencyListViewModel()

    @State private var showInstall = false
    @State private var detail: PanelDependency?
    @State private var pendingDelete: PanelDependency?
    @State private var timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Picker("筛选", selection: $model.filter) {
                ForEach(DepFilter.allCases) { item in
                    Text("\(item.rawValue) \(model.count(for: item))").tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            List {
                if let errorText = model.errorText {
                    Section {
                        ErrorBanner(text: errorText)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }

                if model.isLoading && model.deps.isEmpty {
                    LoadingHint(text: "读取依赖列表…")
                        .listRowBackground(Color.clear)
                } else if model.filtered.isEmpty {
                    EmptyStateView(icon: "shippingbox",
                                   title: "还没有依赖",
                                   message: "点右上角「+」装一个：Node.js 包走 npm，Python 包走 pip，系统包走 apt。")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(model.filtered) { dep in
                            DependencyRow(dep: dep, busy: model.busyID == dep.id)
                                .contentShape(Rectangle())
                                .onTapGesture { detail = dep }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !dep.isBusy {
                                        Button(role: .destructive) {
                                            pendingDelete = dep
                                        } label: {
                                            Label("卸载", systemImage: "trash")
                                        }
                                    }
                                    if dep.isBusy {
                                        Button {
                                            guard let client = session.client else { return }
                                            Task { await model.cancel(dep, client: client) }
                                        } label: {
                                            Label("取消", systemImage: "stop.circle")
                                        }
                                        .tint(AppTheme.warning)
                                    } else {
                                        Button {
                                            guard let client = session.client else { return }
                                            Task { await model.reinstall(dep, client: client) }
                                        } label: {
                                            Label("重装", systemImage: "arrow.clockwise")
                                        }
                                        .tint(AppTheme.accent)
                                    }
                                }
                        }
                    } footer: {
                        Text("「重装」会用同一条记录重跑安装命令；「卸载」先跑 pip uninstall / npm uninstall / apt remove，跑完再删记录。正在安装的包不能删，只能取消。")
                            .font(.system(size: 11))
                    }
                }

                Section(header: Text("环境")) {
                    NavigationLink(destination: DependencyMirrorView()) {
                        Label("镜像源", systemImage: "network")
                    }
                    NavigationLink(destination: DependencyRuntimeView()) {
                        Label("运行时环境", systemImage: "cpu")
                    }
                    NavigationLink(destination: DependencyInventoryView()) {
                        Label("已装包清单", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await reload() }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("依赖管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showInstall = true
                } label: {
                    Image(systemName: "plus")
                }
            }
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
        .onReceive(timer) { _ in
            // 有任务在跑时才轮询，闲时完全不发请求。
            guard model.hasBusy else { return }
            Task { await reload(silent: true) }
        }
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
        .sheet(isPresented: $showInstall) {
            NavigationView {
                DependencyInstallView { message in
                    model.flash(message)
                    Task { await reload() }
                }
                .environmentObject(session)
            }
            .navigationViewStyle(.stack)
        }
        .sheet(item: $detail) { dep in
            NavigationView {
                DependencyDetailView(dependency: dep) {
                    Task { await reload(silent: true) }
                }
                .environmentObject(session)
            }
            .navigationViewStyle(.stack)
        }
        .confirmationDialog("卸载会先执行卸载命令，再从面板记录里删掉这个依赖。",
                            isPresented: Binding(
                                get: { pendingDelete != nil },
                                set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("卸载", role: .destructive) {
                if let dep = pendingDelete {
                    pendingDelete = nil
                    guard let client = session.client else { return }
                    Task { await model.delete(dep, client: client) }
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private func reload(silent: Bool = false) async {
        guard let client = session.client else { return }
        await model.load(client: client, silent: silent)
    }
}

private struct DependencyRow: View {
    let dep: PanelDependency
    let busy: Bool

    private var statusColor: Color {
        switch dep.status {
        case "installed": return AppTheme.success
        case "installing", "queued": return AppTheme.running
        case "removing": return AppTheme.warning
        case "failed": return AppTheme.failure
        default: return AppTheme.idle
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: dep.typeIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(dep.isInstalled ? AppTheme.accent : AppTheme.idle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(dep.name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Text(dep.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if busy {
                ProgressView().scaleEffect(0.7)
            } else {
                StatusBadge(text: dep.statusText, color: statusColor, compact: true)
            }
        }
        .padding(.vertical, 3)
    }
}
