import SwiftUI
import UIKit

@MainActor
final class SystemConfigViewModel: ObservableObject {
    @Published private(set) var items: [PanelConfigItem] = []
    @Published private(set) var drafts: [String: String] = [:]
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorText: String?
    @Published var toast: String?

    /// 载入时的原始值，用来算「改了哪几项」，保存时只提交差异。
    private var original: [String: String] = [:]

    var groups: [ConfigSection] { ConfigSection.build(from: items) }

    var changedKeys: [String] {
        drafts.filter { key, value in original[key] != value }
            .keys
            .sorted()
    }

    var hasChanges: Bool { !changedKeys.isEmpty }

    func value(for key: String) -> String { drafts[key] ?? "" }

    func setValue(_ value: String, for key: String) {
        drafts[key] = value
    }

    func load(client: APIClient, silent: Bool = false) async {
        if !silent && items.isEmpty { isLoading = true }
        errorText = nil
        do {
            let loaded = try await client.fetchConfigs()
            items = loaded
            original = Dictionary(uniqueKeysWithValues: loaded.map { ($0.key, $0.value) })
            drafts = original
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    func discardChanges() {
        drafts = original
        errorText = nil
    }

    /// 数字项在提交前校验：面板对非法值只回一句「配置值不合法」，不如本地先说清楚。
    private func validationMessage() -> String? {
        for item in items where item.kind == .number {
            let raw = (drafts[item.key] ?? "").trimmingCharacters(in: .whitespaces)
            guard let number = Double(raw) else {
                return "「\(item.title)」需要填数字"
            }
            if let min = item.minValue, number < min {
                return "「\(item.title)」不能小于 \(Int(min))"
            }
            if let max = item.maxValue, number > max {
                return "「\(item.title)」不能大于 \(Int(max))"
            }
        }
        return nil
    }

    func save(client: APIClient) async {
        let keys = changedKeys
        guard !keys.isEmpty else { return }
        if let message = validationMessage() {
            errorText = message
            return
        }
        isSaving = true
        errorText = nil
        do {
            var payload: [String: String] = [:]
            for key in keys { payload[key] = drafts[key] ?? "" }
            let message = try await client.setConfigs(payload)
            original = drafts
            flash(message ?? "已保存 \(keys.count) 项设置")
            // 面板可能对值做归一化（例如时区别名），保存后重新读一遍以库里为准。
            await load(client: client, silent: true)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isSaving = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// 系统设置页：面板 `/configs` 的 57 个注册项，按 7 个分组渲染。
///
/// 控件由 `value_type` 决定，面板以后新增配置项，这里不用改代码就能显示（未知类型退化成文本框）。
struct SystemConfigView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = SystemConfigViewModel()

    @State private var revealed: Set<String> = []

    var body: some View {
        List {
            if let errorText = model.errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if model.hasChanges {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(AppTheme.warning)
                        Text("已修改 \(model.changedKeys.count) 项，点右上角「保存」生效")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(AppTheme.warning.opacity(0.10))
                }
            }

            if model.isLoading && model.items.isEmpty {
                LoadingHint(text: "读取系统设置…")
                    .listRowBackground(Color.clear)
            } else if model.items.isEmpty {
                EmptyStateView(icon: "slider.horizontal.3",
                               title: "读不到系统设置",
                               message: "这个接口需要管理员权限")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    } header: {
                        HStack(spacing: 5) {
                            Image(systemName: group.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                            Text(group.title)
                        }
                    } footer: {
                        if let note = group.note {
                            Text(note)
                                .font(.system(size: 11))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("系统设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if model.isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button("保存") {
                        Task { await save() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .disabled(!model.hasChanges)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        model.discardChanges()
                    } label: {
                        Label("撤销全部修改", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.hasChanges)
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("重新读取", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button {
                        UIPasteboard.general.string = model.changedKeys
                            .map { "\($0)=\(model.value(for: $0))" }
                            .joined(separator: "\n")
                    } label: {
                        Label("复制改动内容", systemImage: "doc.on.doc")
                    }
                    .disabled(!model.hasChanges)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
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
    }

    // MARK: - 单行

    @ViewBuilder
    private func row(_ item: PanelConfigItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.kind == .multiline {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                multilineField(item)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if item.isReadOnly {
                        Text(item.readOnlyText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        control(item)
                    }
                }
            }

            if let hint = item.rangeHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if let hint = item.valueHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if let detail = item.detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(_ item: PanelConfigItem) -> some View {
        switch item.kind {
        case .flag:
            Toggle("", isOn: Binding(
                get: { model.value(for: item.key) == "true" },
                set: { model.setValue($0 ? "true" : "false", for: item.key) }))
                .labelsHidden()
                .scaleEffect(0.85)

        case .number:
            TextField("", text: textBinding(item))
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .frame(maxWidth: 110)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

        case .choice:
            Picker(item.title, selection: textBinding(item)) {
                ForEach(item.options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .secret:
            HStack(spacing: 6) {
                Group {
                    if revealed.contains(item.key) {
                        TextField("", text: textBinding(item))
                    } else {
                        SecureField("", text: textBinding(item))
                    }
                }
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 170)

                Button {
                    if revealed.contains(item.key) {
                        revealed.remove(item.key)
                    } else {
                        revealed.insert(item.key)
                    }
                } label: {
                    Image(systemName: revealed.contains(item.key) ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

        case .multiline, .text:
            TextField("", text: textBinding(item))
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 190)
        }
    }

    private func multilineField(_ item: PanelConfigItem) -> some View {
        TextEditor(text: textBinding(item))
            .font(.system(size: 12, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 76)
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
    }

    private func textBinding(_ item: PanelConfigItem) -> Binding<String> {
        Binding(get: { model.value(for: item.key) },
                set: { model.setValue($0, for: item.key) })
    }

    // MARK: - 动作

    private func reload() async {
        guard let client = session.client else { return }
        await model.load(client: client)
    }

    private func save() async {
        guard let client = session.client else { return }
        await model.save(client: client)
    }
}
