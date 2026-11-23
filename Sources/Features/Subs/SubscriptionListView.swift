import SwiftUI

@MainActor
final class SubscriptionListViewModel: ObservableObject {
    @Published var subs: [PanelSubscription] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var pullingID: Int?

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

struct SubscriptionListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SubscriptionListViewModel()
    @State private var errorText: String?
    @State private var toast: String?

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
                            row(sub)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        pull(sub)
                                    } label: {
                                        Label("立即拉取", systemImage: "arrow.down.circle")
                                    }
                                    .tint(AppTheme.accent)
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
                        Text("左滑「立即拉取」会触发一次同步；拉取进度可在面板网页端查看。")
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
                    .transition(.opacity)
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

            if model.pullingID == sub.id {
                ProgressView().scaleEffect(0.75)
            } else {
                Button {
                    pull(sub)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 17))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
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

    private func pull(_ sub: PanelSubscription) {
        model.pullingID = sub.id
        errorText = nil
        Task {
            do {
                let client = try session.requireClient()
                try await client.pullSubscription(id: sub.id)
                showToast("已触发「\(sub.displayName)」同步")
                await load()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
            model.pullingID = nil
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

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { toast = nil }
        }
    }
}
