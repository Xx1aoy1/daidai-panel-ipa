import SwiftUI

@MainActor
final class IPWhitelistViewModel: ObservableObject {
    @Published var entries: [IPWhitelistEntry] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var toast: String?

    func load(client: APIClient) async {
        if entries.isEmpty { isLoading = true }
        errorText = nil
        do {
            entries = try await client.fetchIPWhitelist()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func add(ip: String, remarks: String, client: APIClient) async -> String? {
        do {
            let entry = try await client.addIPWhitelist(ip: ip, remarks: remarks)
            await load(client: client)
            return entry?.ip
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            return nil
        }
    }

    func remove(_ entry: IPWhitelistEntry, client: APIClient) async {
        do {
            let message = try await client.removeIPWhitelist(id: entry.id)
            entries.removeAll { $0.id == entry.id }
            flash(message ?? "删除成功")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
    }

    func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// IP 白名单：面板没有「开关」，**列表非空即是开启状态**，空列表才是不限制。
/// 加进去的那一瞬间就开始生效，不在名单里的 IP 立刻登不进来（已登录的会话不受影响）。
struct IPWhitelistView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = IPWhitelistViewModel()

    @State private var showAdd = false
    @State private var pendingDelete: IPWhitelistEntry?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.warning)
                    Text(model.entries.isEmpty
                         ? "当前列表为空：不限制登录来源，任何 IP 都能登录。"
                         : "已开启限制：只有列表里的 IP / 网段能登录，其余 IP 会被面板直接拒绝（HTTP 403「当前 IP 不在登录白名单中」）。")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            } header: {
                Text("状态")
            } footer: {
                Text("这条限制是**边加边生效**的：添加第一条的瞬间就切换到「只允许名单内」。加之前先确认你自己的出口 IP 在里面，否则下一次登录会被自己关在门外（已登录的会话不会立刻断开）。")
                    .font(.system(size: 11))
            }

            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if model.isLoading && model.entries.isEmpty {
                Section { LoadingHint(text: "读取白名单…") }
            } else if model.entries.isEmpty {
                Section {
                    EmptyStateView(icon: "network",
                                   title: "白名单是空的",
                                   message: "空列表等同于不限制，添加第一条后限制立刻生效")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(model.entries) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.ip.contains("/") || entry.ip.contains("*")
                                  ? "network"
                                  : "personalhotspot")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.ip)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text(entry.remarksText)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("添加于 \(entry.createdText)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = entry
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("\(model.entries.count) 条")
                }
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("添加 IP / 网段", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .medium))
                }
            } footer: {
                Text("支持三种写法：单个 IP（`203.0.113.7`）、CIDR 网段（`203.0.113.0/24`）、IPv4 通配（`203.0.113.*`）。重复添加会被面板拒掉。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("IP 白名单")
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
                    .padding(.bottom, 26)
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationView {
                IPWhitelistAddView { ip, remarks in
                    guard let client = session.client else { return "登录态已失效，请重新登录" }
                    if let added = await model.add(ip: ip, remarks: remarks, client: client) {
                        model.flash("已添加 \(added)")
                        return nil
                    }
                    return model.errorText ?? "添加失败"
                }
            }
            .navigationViewStyle(.stack)
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let target = pendingDelete {
                    Task { await remove(target) }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteTitle: String {
        guard let target = pendingDelete else { return "" }
        if model.entries.count == 1 {
            return "删掉最后一条后白名单变空，等于关闭限制、任何 IP 都能登录。确定删除 \(target.ip)？"
        }
        return "删除 \(target.ip)？删除后该来源将无法登录。"
    }

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }

    private func remove(_ entry: IPWhitelistEntry) async {
        guard let client = session.client else { return }
        await model.remove(entry, client: client)
    }
}

/// 添加白名单：先做个本地格式自检，省得为一个拼错的网段白跑一次请求。
private struct IPWhitelistAddView: View {
    @Environment(\.dismiss) private var dismiss

    /// 返回 nil 表示添加成功；返回字符串表示错误文案，留在页面上显示。
    let onAdd: (String, String) async -> String?

    @State private var ip = ""
    @State private var remarks = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                TextField("如 203.0.113.7 / 203.0.113.0/24 / 203.0.113.*", text: $ip)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 14, design: .monospaced))
            } header: {
                Text("IP 或网段")
            } footer: {
                Text("面板会做规范化：写 `203.0.113.*` 也能识别成网段。IPv6 请用 CIDR 写法。")
                    .font(.system(size: 11))
            }

            Section {
                TextField("备注说明（可选）", text: $remarks)
                    .font(.system(size: 14))
            } header: {
                Text("备注")
            }

            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("添加并立即生效")
                        Spacer()
                        if isSubmitting { ProgressView().scaleEffect(0.8) }
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(isSubmitting || trimmedIP.isEmpty)
            } footer: {
                Text("添加成功后限制立刻生效，请确认当前设备的出口 IP 也在名单里。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("添加白名单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private var trimmedIP: String {
        ip.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        if let problem = IPWhitelistRules.validate(trimmedIP) {
            errorText = problem
            return
        }
        isSubmitting = true
        errorText = await onAdd(trimmedIP, remarks)
        isSubmitting = false
        if errorText == nil { dismiss() }
    }
}

/// 面板侧 `netutil.NormalizeIPWhitelistEntry` 的轻量版：只挡明显写错的情况，
/// 真正的规范化（通配转 CIDR、IPv6 压缩等）交给服务端，报错文案也直接用它的。
enum IPWhitelistRules {
    static func validate(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "IP 或网段不能为空" }
        if text.contains(" ") { return "IP 里不能有空格" }

        if text.contains("/") {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let prefix = Int(parts[1]) else {
                return "网段格式不对，形如 203.0.113.0/24"
            }
            let isV6 = parts[0].contains(":")
            let maxPrefix = isV6 ? 128 : 32
            if prefix < 0 || prefix > maxPrefix {
                return "掩码位数超出范围（IPv4 0-32，IPv6 0-128）"
            }
            return nil
        }

        if text.contains("*") {
            // 只支持 IPv4 通配，且 * 只能出现在最后一段。
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4, parts.last == "*" else {
                return "通配只能写成 203.0.113.* 这种末段形式"
            }
            for part in parts.dropLast() {
                guard let value = Int(part), (0...255).contains(value) else {
                    return "IPv4 段取值要在 0-255 之间"
                }
            }
            return nil
        }

        if text.contains(":") { return nil }   // IPv6 单地址，交给服务端校验
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return "IP 地址格式无效，IPv4 需要四段" }
        for part in parts {
            guard let value = Int(part), (0...255).contains(value) else {
                return "IPv4 段取值要在 0-255 之间"
            }
        }
        return nil
    }
}
