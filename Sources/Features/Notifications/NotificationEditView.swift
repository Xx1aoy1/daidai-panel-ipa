import SwiftUI

/// 新建 / 编辑一个通知渠道。
///
/// 表单是按 `/notifications/types` 的字段定义动态渲染的，面板以后加字段不用改客户端；
/// 面板没定义的字段当然也无从提交。保存时统一把值转成字符串拼成 `config` JSON 字符串。
struct NotificationEditView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let type: NotifyChannelType?
    let channel: NotifyChannel?
    let onSaved: () -> Void

    @State private var name: String
    @State private var values: [String: String]
    @State private var pushScope: String
    @State private var revealedSecrets: Set<String> = []
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var errorText: String?
    @State private var toast: String?

    init(type: NotifyChannelType?, channel: NotifyChannel?, onSaved: @escaping () -> Void) {
        self.type = type
        self.channel = channel
        self.onSaved = onSaved

        let initial = channel.map { NotifyDraft.from(channel: $0) }
        _name = State(initialValue: initial?.name ?? "")
        _values = State(initialValue: initial?.fields ?? [:])
        _pushScope = State(initialValue: initial?.pushScope ?? "default")
    }

    private var isEditing: Bool { channel != nil }
    private var fields: [NotifyField] { type?.fields ?? [] }

    private var missingRequired: [String] {
        fields.compactMap { field in
            guard field.required == true else { return nil }
            let value = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? field.title : nil
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && missingRequired.isEmpty
            && !isSaving
    }

    var body: some View {
        Form {
            Section {
                TextField("渠道名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Text("类型")
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: type?.systemImage ?? "bell.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(type?.name ?? channel?.type ?? "未知")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.secondary)
                }

                Picker("推送范围", selection: $pushScope) {
                    Text("默认推送").tag("default")
                    Text("绑定推送").tag("bound")
                }
            } header: {
                Text("基本信息")
            } footer: {
                Text(pushScope == "bound"
                     ? "绑定推送：只在该任务显式绑定了本渠道时发送，不参与全局广播。"
                     : "默认推送：任务执行结果会广播到这个渠道。")
                    .font(.system(size: 11))
            }

            Section {
                ForEach(fields) { field in
                    fieldRow(field)
                }
                if fields.isEmpty {
                    Text("这个渠道没有可配置字段")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("渠道配置")
            } footer: {
                if let missing = missingRequired.first {
                    Text("还缺必填项：\(missing)")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.failure)
                } else {
                    Text("凭据类字段（Token / 密码 / Secret）保存在面板数据库里，客户端只是转发，不落盘。")
                        .font(.system(size: 11))
                }
            }

            if isEditing {
                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Label("发送测试消息", systemImage: "paperplane.fill")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if isTesting { ProgressView().scaleEffect(0.75) }
                        }
                    }
                    .disabled(isTesting || isSaving)
                } footer: {
                    Text("测试用的是**面板里已保存的**配置。改了上面的字段请先保存，否则测的还是旧配置。")
                        .font(.system(size: 11))
                }
            }

            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isEditing ? "编辑渠道" : "新建渠道")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text("保存").fontWeight(.semibold)
                    }
                }
                .disabled(!canSave)
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
    }

    // MARK: - 动态字段

    @ViewBuilder
    private func fieldRow(_ field: NotifyField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(field.title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if field.required == true {
                    Text("*")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.failure)
                }
            }

            switch field.kind {
            case .input:
                TextField(field.placeholder ?? "", text: binding(for: field.key))
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

            case .password:
                HStack(spacing: 8) {
                    Group {
                        if revealedSecrets.contains(field.key) {
                            TextField(field.placeholder ?? "", text: binding(for: field.key))
                        } else {
                            SecureField(field.placeholder ?? "", text: binding(for: field.key))
                        }
                    }
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        if revealedSecrets.contains(field.key) {
                            revealedSecrets.remove(field.key)
                        } else {
                            revealedSecrets.insert(field.key)
                        }
                    } label: {
                        Image(systemName: revealedSecrets.contains(field.key) ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            case .select:
                // Picker 的首参只接受 LocalizedStringKey 字面量，变量标题要放到 label 里。
                Picker(selection: binding(for: field.key)) {
                    if field.required != true {
                        Text("未设置").tag("")
                    }
                    ForEach(field.options ?? []) { option in
                        Text(option.label).tag(option.value)
                    }
                } label: {
                    Text(field.title)
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .textarea:
                // 部署目标是 iOS 15，用不了 `TextField(axis: .vertical)`，退回 TextEditor + 固定高度。
                TextEditor(text: binding(for: field.key))
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .frame(minHeight: 72)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 2)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    // MARK: - 动作

    private func save() async {
        guard let client = session.client else { return }
        isSaving = true
        errorText = nil

        let draft = NotifyDraft(name: name.trimmingCharacters(in: .whitespaces),
                                type: type?.type ?? channel?.type ?? "",
                                fields: values,
                                pushScope: pushScope)

        do {
            if let channel {
                try await client.updateNotifyChannel(id: channel.id, draft: draft)
                flash("已保存")
            } else {
                _ = try await client.createNotifyChannel(draft)
                flash("已创建")
            }
            onSaved()
            try? await Task.sleep(nanoseconds: 450_000_000)
            dismiss()
        } catch {
            if !session.handle(error) {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
        isSaving = false
    }

    private func runTest() async {
        guard let client = session.client, let channel else { return }
        isTesting = true
        errorText = nil
        do {
            try await client.testNotifyChannel(id: channel.id)
            flash("测试消息已发出")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isTesting = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}
