import SwiftUI

/// 通用「起个名字」表单：新建文件 / 新建文件夹 / 重命名都用它。
/// 面板的叶子名校验（空、`/`、`.`、`..`、`<>:"|?*`、控制字符）在这里先拦一次。
struct ScriptNamePrompt: View {
    @Environment(\.presentationMode) private var presentationMode

    let title: String
    let placeholder: String
    let confirmTitle: String
    let hint: String?
    let initialValue: String
    let onConfirm: (String) -> Void

    @State private var text: String
    @State private var errorText: String?

    init(title: String,
         placeholder: String,
         confirmTitle: String = "确定",
         hint: String? = nil,
         initialValue: String = "",
         onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.hint = hint
        self.initialValue = initialValue
        self.onConfirm = onConfirm
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } footer: {
                    if let hint {
                        Text(hint).font(.system(size: 11))
                    }
                }

                if let errorText {
                    Section { ErrorBanner(text: errorText) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(confirmTitle) {
                        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let problem = ScriptPath.validate(name: name) {
                            errorText = problem
                            return
                        }
                        onConfirm(name)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// 目录选择器：移动脚本时选目标目录。根目录永远在第一位。
struct ScriptDirectoryPicker: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var store: ScriptTreeStore

    let title: String
    let currentDir: String
    let onPick: (String) -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(store.directoryOptions()) { option in
                        Button {
                            onPick(option.path)
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: option.path.isEmpty ? "tray.full" : "folder")
                                    .font(.system(size: 12))
                                    .foregroundColor(option.path.isEmpty ? AppTheme.accent : AppTheme.warning)
                                Text(option.title)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if option.path == currentDir {
                                    Text("当前")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading, CGFloat(option.depth) * 12)
                        }
                    }
                } footer: {
                    Text("移动后原路径立刻失效；同名文件会被面板直接覆盖，不会提示。")
                        .font(.system(size: 11))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// 复制脚本：先选目标目录，再确认新文件名（默认「原名_copy」）。
struct ScriptCopySheet: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject var store: ScriptTreeStore

    let sourcePath: String
    let onConfirm: (String, String) -> Void

    @State private var name: String
    @State private var targetDir: String
    @State private var errorText: String?

    init(store: ScriptTreeStore, sourcePath: String, onConfirm: @escaping (String, String) -> Void) {
        _store = ObservedObject(wrappedValue: store)
        self.sourcePath = sourcePath
        self.onConfirm = onConfirm

        let leaf = ScriptPath.leaf(of: sourcePath)
        let ext = (leaf as NSString).pathExtension
        let base = (leaf as NSString).deletingPathExtension
        let suggestion = ext.isEmpty ? "\(base)_copy" : "\(base)_copy.\(ext)"
        _name = State(initialValue: suggestion)
        _targetDir = State(initialValue: ScriptPath.dir(of: sourcePath))
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("新文件名", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("文件名")
                } footer: {
                    Text("只填文件名，不能带路径。同名文件会被覆盖。")
                        .font(.system(size: 11))
                }

                Section {
                    ForEach(store.directoryOptions()) { option in
                        Button {
                            targetDir = option.path
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: targetDir == option.path ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(targetDir == option.path ? AppTheme.success : .secondary)
                                Image(systemName: option.path.isEmpty ? "tray.full" : "folder")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.warning)
                                Text(option.title)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, CGFloat(option.depth) * 10)
                        }
                    }
                } header: {
                    Text("目标目录")
                }

                if let errorText {
                    Section { ErrorBanner(text: errorText) }
                }
            }
            .navigationTitle("复制到…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("复制") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let problem = ScriptPath.validate(name: trimmed) {
                            errorText = problem
                            return
                        }
                        onConfirm(targetDir, trimmed)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
