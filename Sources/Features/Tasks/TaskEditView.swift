import SwiftUI

struct TaskEditView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.presentationMode) private var presentationMode

    private let original: PanelTask?
    private let onSaved: () -> Void

    @State private var draft: TaskDraft
    @State private var errorText: String?
    @State private var isSaving = false

    init(task: PanelTask?, onSaved: @escaping () -> Void = {}) {
        self.original = task
        self.onSaved = onSaved
        if let task {
            _draft = State(initialValue: TaskDraft(task: task))
        } else {
            _draft = State(initialValue: TaskDraft())
        }
    }

    private var isEditing: Bool { original != nil }

    var body: some View {
        NavigationView {
            Form {
                if let errorText {
                    Section {
                        ErrorBanner(text: errorText)
                    }
                }

                Section(header: Text("基本信息")) {
                    TextField("任务名称", text: $draft.name)
                        .textInputAutocapitalization(.never)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("执行命令")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextEditor(text: $draft.command)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 88)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                }

                Section {
                    Picker("任务类型", selection: $draft.taskType) {
                        Text("Cron 定时").tag("cron")
                        Text("手动触发").tag("manual")
                    }
                    .pickerStyle(.segmented)

                    if draft.taskType == "cron" {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Cron 表达式")
                                    .font(.system(size: 13))
                                Spacer()
                                Text(draft.cronLines.count > 1
                                     ? "\(draft.cronLines.count) 条规则"
                                     : "一条规则")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            TextEditor(text: $draft.cronExpression)
                                .font(.system(size: 14, design: .monospaced))
                                .frame(minHeight: 58)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }

                        Menu {
                            ForEach(CronPreset.allCases) { preset in
                                Button("\(preset.rawValue)  (\(preset.expression))") {
                                    appendCron(preset.expression)
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "wand.and.stars")
                                Text("追加一条常用规则")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                            }
                            .font(.system(size: 13))
                        }
                    }
                } header: {
                    Text("调度")
                } footer: {
                    Text("面板支持一个任务挂多条定时规则，**每行一条**。客户端会按行原样提交，不会把多余的规则覆盖掉。")
                        .font(.system(size: 11))
                }

                Section(header: Text("执行控制"),
                        footer: Text("超时为 0 表示不限制；重试间隔按面板默认策略执行。")) {
                    Stepper("超时：\(draft.timeout == 0 ? "不限制" : "\(draft.timeout) 秒")",
                            value: $draft.timeout, in: 0...86400, step: 30)
                    Stepper("失败重试：\(draft.maxRetries) 次",
                            value: $draft.maxRetries, in: 0...10)
                    HStack {
                        Text("成功退出码")
                        Spacer()
                        TextField("0", text: $draft.successExitCodes)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 14, design: .monospaced))
                            .keyboardType(.numbersAndPunctuation)
                    }
                    Toggle("允许多实例同时运行", isOn: $draft.allowMultipleInstances)
                }

                Section(header: Text("通知")) {
                    Toggle("失败时通知", isOn: $draft.notifyOnFailure)
                    Toggle("成功时通知", isOn: $draft.notifyOnSuccess)
                }
            }
            .navigationTitle(isEditing ? "编辑任务" : "新建任务")
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

    private func appendCron(_ expression: String) {
        var lines = draft.cronLines
        // 第一条如果是默认占位或空，直接替换掉，别让用户先手动删。
        if lines.count == 1, lines[0].isEmpty {
            lines = []
        }
        lines.append(expression)
        draft.cronExpression = lines.joined(separator: "\n")
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
                    try await client.updateTask(id: original.id, draft: draft)
                } else {
                    try await client.createTask(draft)
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
}
