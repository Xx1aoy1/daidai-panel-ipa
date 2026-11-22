import SwiftUI

struct EnvEditView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.presentationMode) private var presentationMode

    private let original: EnvVar?
    private let onSaved: () -> Void

    @State private var draft: EnvDraft
    @State private var errorText: String?
    @State private var isSaving = false
    @State private var showValue = false

    init(env: EnvVar?, onSaved: @escaping () -> Void = {}) {
        self.original = env
        self.onSaved = onSaved
        if let env {
            _draft = State(initialValue: EnvDraft(env: env))
            _showValue = State(initialValue: !env.looksSensitive)
        } else {
            _draft = State(initialValue: EnvDraft())
            _showValue = State(initialValue: true)
        }
    }

    private var isEditing: Bool { original != nil }

    var body: some View {
        NavigationView {
            Form {
                if let errorText {
                    Section { ErrorBanner(text: errorText) }
                }

                Section(header: Text("变量"),
                        footer: Text("名称为大写字母、数字与下划线；同名变量可并存，任务会全部注入。")) {
                    TextField("名称，如 JD_COOKIE", text: $draft.name)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("值")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(showValue ? "隐藏" : "显示") {
                                showValue.toggle()
                            }
                            .font(.system(size: 11))
                        }

                        ZStack(alignment: .topLeading) {
                            if showValue {
                                TextEditor(text: $draft.value)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(minHeight: 90)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                            } else {
                                SecureField("变量值", text: $draft.value)
                                    .font(.system(size: 13, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .padding(.vertical, 8)
                            }
                        }
                    }

                    TextField("备注（可选）", text: $draft.remarks)
                    TextField("分组（可选），如 京东", text: $draft.group)
                    Toggle("启用", isOn: $draft.enabled)
                }

                if isEditing, let original, let group = original.group, !group.isEmpty {
                    Section(header: Text("当前分组")) {
                        KeyValueRow(label: "分组", value: group)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        if let original {
                            delete(id: original.id)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(isEditing ? "删除这个变量" : "取消")
                            Spacer()
                        }
                    }
                    .disabled(!isEditing)
                }
            }
            .navigationTitle(isEditing ? "编辑变量" : "新建变量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("保存").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        if let validation = draft.validationError {
            errorText = validation
            return
        }
        isSaving = true
        errorText = nil

        Task {
            do {
                let client = try session.requireClient()
                if let original {
                    try await client.updateEnv(id: original.id, draft: draft)
                } else {
                    try await client.createEnv(draft)
                }
                onSaved()
                presentationMode.wrappedValue.dismiss()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
            isSaving = false
        }
    }

    private func delete(id: Int) {
        isSaving = true
        Task {
            do {
                let client = try session.requireClient()
                try await client.deleteEnv(id: id)
                onSaved()
                presentationMode.wrappedValue.dismiss()
            } catch {
                if !session.handle(error) {
                    errorText = (error as? PanelError)?.message ?? error.localizedDescription
                }
            }
            isSaving = false
        }
    }
}
