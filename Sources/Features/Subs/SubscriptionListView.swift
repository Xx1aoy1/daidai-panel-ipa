import SwiftUI

@MainActor
final class SubscriptionListViewModel: ObservableObject {
    @Published var subs: [PanelSubscription] = []
    @Published var isLoading = false
    @Published var errorText: String?

    func load(client: APIClient) async {
        if subs.isEmpty { isLoading = true }
        errorText = nil
        do {
            subs = try await client.fetchSubscriptions()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }
}

/// 订阅列表。点进去就是拉取进度页（进页面会立刻触发一次拉取），
/// 这样「拉代码」和「看输出」是一条路，不用先点按钮再找日志。
struct SubscriptionListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SubscriptionListViewModel()
    @State private var errorText: String?

    var body: some View {
        Group {
            if let errorText = model.errorText, model.subs.isEmpty {
                VStack(spacing: 12) {
                    ErrorBanner(text: errorText)
                    Button("重试") { Task { await load() } }
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(16)
            } else if model.isLoading && model.subs.isEmpty {
                VStack {
                    LoadingHint(text: "加载订阅…")
                    Spacer()
                }
            } else if model.subs.isEmpty {
                VStack {
                    EmptyStateView(icon: "arrow.triangle.2.circlepath",
                                   title: "还没有订阅",
                                   message: "订阅需要在面板网页端创建")
                    Spacer()
                }
            } else {
                List {
                    if let errorText {
                        Section { ErrorBanner(text: errorText) }
                    }
                    Section {
                        ForEach(model.subs) { sub in
                            NavigationLink(destination: SubscriptionPullView(subscription: sub)) {
                                row(sub)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    toggle(sub)
                                } label: {
                                    Label(sub.isEnabled ? "禁用" : "启用",
                                          systemImage: sub.isEnabled ? "pause.circle" : "play.circle")
                                }
                                .tint(sub.isEnabled ? AppTheme.warning : AppTheme.success)
                            }
                        }
                    } footer: {
                        Text("点进去会自动拉取一次并把面板的实时输出铺出来，可以中途停止；左滑切换启用/禁用。")
                            .font(.system(size: 11))
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle("订阅")
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
        .task { await load() }
    }

    private func row(_ sub: PanelSubscription) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(sub.isEnabled ? AppTheme.success : AppTheme.idle)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(sub.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    StatusBadge(text: sub.typeText, color: AppTheme.accent, compact: true)
                }
                if let url = sub.url, !url.isEmpty {
                    Text(url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Text("同步 \(sub.scheduleText)")
                    Text("· 上次拉取 \(sub.pullText)")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func load() async {
        do {
            let client = try session.requireClient()
            await model.load(client: client)
        } catch {
            model.errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    private func toggle(_ sub: PanelSubscription) {
        Task {
            do {
                let client = try session.requireClient()
                try await client.setSubscriptionEnabled(id: sub.id, enabled: !sub.isEnabled)
                await load()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
        }
    }
}
