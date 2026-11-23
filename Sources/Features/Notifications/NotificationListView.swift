import SwiftUI

@MainActor
final class NotificationListViewModel: ObservableObject {
    @Published var channels: [NotifyChannel] = []
    @Published var types: [NotifyChannelType] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toast: String?
    @Published var busyID: Int?

    private var typeMap: [String: NotifyChannelType] = [:]

    func type(for key: String) -> NotifyChannelType? { typeMap[key] }

    func load(client: APIClient) async {
        if channels.isEmpty { isLoading = true }
        errorText = nil
        do {
            async let channelTask = client.fetchNotifyChannels()
            async let typeTask = client.fetchNotifyTypes()
            let (loadedChannels, loadedTypes) = try await (channelTask, typeTask)
            channels = loadedChannels
            types = loadedTypes
            typeMap = Dictionary(uniqueKeysWithValues: loadedTypes.map { ($0.type, $0) })
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func setEnabled(_ channel: NotifyChannel, enabled: Bool, client: APIClient) async {
        busyID = channel.id
        do {
            try await client.setNotifyChannelEnabled(id: channel.id, enabled: enabled)
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                channels[index].enabled = enabled
            }
            flash(enabled ? "已启用" : "已停用")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        busyID = nil
    }

    /// 发一条真实测试消息。成功/失败都会写回渠道的 last_test_status，这里同步更新本地状态。
    func test(_ channel: NotifyChannel, client: APIClient) async {
        busyID = channel.id
        toast = nil
        do {
            try await client.testNotifyChannel(id: channel.id)
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                channels[index].lastTestStatus = "success"
                channels[index].lastTestAt = ISO8601DateFormatter().string(from: Date())
            }
            flash("测试消息已发出，请检查接收端")
        } catch {
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                channels[index].lastTestStatus = "failed"
            }
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        busyID = nil
    }

    func delete(_ channel: NotifyChannel, client: APIClient) async {
        busyID = channel.id
        do {
            try await client.deleteNotifyChannel(id: channel.id)
            channels.removeAll { $0.id == channel.id }
            flash("已删除「\(channel.name)」")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        busyID = nil
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct NotificationListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = NotificationListViewModel()

    /// 同一个视图上挂多个 `.sheet` 在 iOS 15 上只有最后一个稳定生效，
    /// 所以统一收成一个状态机，「选类型 → 建渠道」的交接也走它。
    private enum ActiveSheet: Identifiable {
        case pickType
        case create(NotifyChannelType)
        case edit(NotifyChannel)

        var id: String {
            switch self {
            case .pickType: return "pick"
            case .create(let type): return "create-\(type.type)"
            case .edit(let channel): return "edit-\(channel.id)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var pendingDelete: NotifyChannel?

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if model.isLoading && model.channels.isEmpty {
                LoadingHint(text: "读取通知渠道…")
                    .listRowBackground(Color.clear)
            } else if model.channels.isEmpty {
                EmptyStateView(icon: "bell.slash",
                               title: "还没有通知渠道",
                               message: "加一个 Bark / Telegram / 邮件渠道，任务跑完就能推到手机上")
                    .listRowBackground(Color.clear)
            } else {
                section(title: "已启用", items: model.channels.filter { $0.enabled })
                section(title: "已停用", items: model.channels.filter { !$0.enabled })
            }

            Section {
                Button {
                    activeSheet = .pickType
                } label: {
                    Label("添加通知渠道", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                }
                .disabled(model.types.isEmpty)
            } footer: {
                Text("渠道配置里含 Bot Token、SMTP 密码这类凭据，面板只允许管理员读写，所以这个入口仅 admin 可用。点「测试」会给渠道真实发一条消息。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通知渠道")
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
        .refreshable { await reload() }
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .pickType:
                NotifyTypePickerView(types: model.types) { picked in
                    activeSheet = nil
                    // 等前一个 sheet 收完再弹编辑页，否则 iOS 会吞掉第二次 present。
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        activeSheet = .create(picked)
                    }
                }
                .environmentObject(session)

            case .create(let type):
                NavigationView {
                    NotificationEditView(type: type, channel: nil) {
                        Task { await reload() }
                    }
                    .environmentObject(session)
                }
                .navigationViewStyle(.stack)

            case .edit(let channel):
                NavigationView {
                    NotificationEditView(type: model.type(for: channel.type), channel: channel) {
                        Task { await reload() }
                    }
                    .environmentObject(session)
                }
                .navigationViewStyle(.stack)
            }
        }
        .confirmationDialog("删除后这个渠道不再收到任何通知，配置里的凭据也会一起删掉。",
                            isPresented: Binding(
                                get: { pendingDelete != nil },
                                set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除渠道", role: .destructive) {
                if let channel = pendingDelete {
                    pendingDelete = nil
                    Task {
                        if let client = session.client {
                            await model.delete(channel, client: client)
                        }
                    }
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    @ViewBuilder
    private func section(title: String, items: [NotifyChannel]) -> some View {
        if !items.isEmpty {
            Section(header: Text(title)) {
                ForEach(items) { channel in
                    NotifyChannelRow(channel: channel,
                                     type: model.type(for: channel.type),
                                     busy: model.busyID == channel.id,
                                     onToggle: { enabled in
                                         guard let client = session.client else { return }
                                         Task { await model.setEnabled(channel, enabled: enabled, client: client) }
                                     })
                        .contentShape(Rectangle())
                        .onTapGesture { activeSheet = .edit(channel) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = channel
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                guard let client = session.client else { return }
                                Task { await model.test(channel, client: client) }
                            } label: {
                                Label("测试", systemImage: "paperplane")
                            }
                            .tint(AppTheme.accent)
                        }
                }
            }
        }
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }
}

private struct NotifyChannelRow: View {
    let channel: NotifyChannel
    let type: NotifyChannelType?
    let busy: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: type?.systemImage ?? "bell.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(channel.enabled ? AppTheme.accent : AppTheme.idle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    if channel.isBound {
                        StatusBadge(text: "绑定", color: AppTheme.warning, compact: true)
                    }
                    if channel.lastTestStatus == "failed" {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.failure)
                    }
                }
                Text("\(type?.name ?? channel.type) · \(channel.summary(using: type))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let count = channel.todaySendCount, count > 0 {
                    Text("今日 \(count) 条")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 4)

            if busy {
                ProgressView().scaleEffect(0.7)
            } else {
                Toggle("", isOn: Binding(get: { channel.enabled }, set: { onToggle($0) }))
                    .labelsHidden()
                    .scaleEffect(0.82)
            }
        }
        .padding(.vertical, 3)
    }
}

/// 新建时先选渠道类型。19 种平铺太长，按用途分组。
private struct NotifyTypePickerView: View {
    let types: [NotifyChannelType]
    let onPick: (NotifyChannelType) -> Void

    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [String])] = [
        ("手机推送", ["bark", "gotify", "ntfy", "pushdeer", "pushme", "chanify", "igot", "pushover"]),
        ("微信 / 企业微信", ["wecom", "wecom_app", "serverchan", "pushplus", "wxpusher"]),
        ("IM 机器人", ["telegram", "dingtalk", "feishu", "qmsg", "discord", "slack"]),
        ("邮件 / 通用", ["email", "webhook", "custom"])
    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(groups.enumerated()), id: \.offset) { entry in
                    let group = entry.element
                    let items = types.filter { group.1.contains($0.type) }
                    if !items.isEmpty {
                        Section(header: Text(group.0)) {
                            ForEach(items) { type in
                                Button {
                                    onPick(type)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: type.systemImage)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 26, height: 26)
                                            .background(AppTheme.accent)
                                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        Text(type.name)
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("\(type.fields.count) 项")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                let known = Set(groups.flatMap { $0.1 })
                let others = types.filter { !known.contains($0.type) }
                if !others.isEmpty {
                    Section(header: Text("其他")) {
                        ForEach(others) { type in
                            Button {
                                onPick(type)
                            } label: {
                                Text(type.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择渠道类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
