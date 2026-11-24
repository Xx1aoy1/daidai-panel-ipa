import SwiftUI
import UIKit

/// 两步验证（`/security/2fa*`）：只作用于当前登录的账号，任何角色都能自己管。
///
/// 面板的流程是「先 setup 拿密钥 → 再 verify 验码才算启用」，
/// 关闭时必须带当前动态码（防的是「会话被劫持就能关掉 2FA」）。
struct TwoFactorView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var enabled: Bool?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var toast: String?

    /// iOS 15 同一个视图挂多个 `.sheet` 只有最后一个稳定生效，统一收进一个状态机。
    @State private var activeSheet: Sheet?

    private enum Sheet: Identifiable {
        case setup
        case disable

        var id: Int { self == .setup ? 0 : 1 }
    }

    var body: some View {
        List {
            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: enabled == true ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 16))
                        .foregroundColor(enabled == true ? AppTheme.success : AppTheme.idle)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(enabled == true ? "已启用" : "未启用")
                            .font(.system(size: 15, weight: .semibold))
                        Text(enabled == true
                             ? "登录时需要额外输入认证器里的 6 位动态码"
                             : "只靠密码登录，密码一旦泄露账号就直接暴露")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if isLoading {
                        ProgressView().scaleEffect(0.8)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("状态")
            } footer: {
                Text("动态码来自 Google Authenticator、Microsoft Authenticator、1Password 等任意 TOTP 应用，面板不提供短信验证。")
                    .font(.system(size: 11))
            }

            Section {
                if enabled == true {
                    Button(role: .destructive) {
                        activeSheet = .disable
                    } label: {
                        Label("关闭两步验证", systemImage: "lock.open")
                            .font(.system(size: 14, weight: .medium))
                    }
                } else {
                    Button {
                        activeSheet = .setup
                    } label: {
                        Label("启用两步验证", systemImage: "lock.shield")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .disabled(enabled == nil)
                }
            } footer: {
                Text(enabled == true
                     ? "关闭需要输入一次当前的动态码：光有登录态关不掉，防止会话被劫持后被人悄悄摘掉 2FA。"
                     : "开启后请立刻把密钥存进认证器并确认能生成验证码，面板不提供备用恢复码，丢了认证器只能靠管理员账号在后台处理。")
                    .font(.system(size: 11))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("两步验证")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .overlay(alignment: .bottom) {
            if let toast {
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .setup:
                NavigationView {
                    TwoFactorSetupSheet { message in
                        activeSheet = nil
                        flash(message)
                        Task { await reload() }
                    }
                    .environmentObject(session)
                }
                .navigationViewStyle(.stack)
            case .disable:
                NavigationView {
                    TwoFactorDisableView { message in
                        activeSheet = nil
                        flash(message)
                        Task { await reload() }
                    }
                    .environmentObject(session)
                }
                .navigationViewStyle(.stack)
            }
        }
    }

    private func reload() async {
        guard let client = session.client else {
            isLoading = false
            return
        }
        do {
            let status = try await client.fetchTwoFactorStatus()
            enabled = status.isEnabled
            errorText = nil
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// 启用流程：进页面就调一次 `POST /security/2fa/setup` 拿密钥，扫完码当场验码。
struct TwoFactorSetupSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let onDone: (String) -> Void

    @State private var setup: TwoFactorSetup?
    @State private var code = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var copied = false

    private var normalizedCode: String {
        code.filter { $0.isNumber }
    }

    var body: some View {
        List {
            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if isLoading {
                Section { LoadingHint(text: "正在申请密钥…") }
            } else if let setup {
                Section {
                    VStack(spacing: 10) {
                        QRCodeImage(text: setup.uri)
                            .frame(width: 190, height: 190)
                            .padding(10)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("用认证器应用扫描上面的二维码")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("第一步 · 扫码")
                }

                Section {
                    HStack(spacing: 8) {
                        Text(setup.secret)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Button {
                            UIPasteboard.general.string = setup.secret
                            copied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                copied = false
                            }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("扫不动就手动输入密钥")
                } footer: {
                    Text("密钥只在这一步显示，关掉这个页面后如果还没验证成功，下次会重新生成一个新的。")
                        .font(.system(size: 11))
                }

                Section {
                    TextField("6 位动态码", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                            Text(isSubmitting ? "验证中…" : "验证并启用")
                            Spacer()
                            if isSubmitting { ProgressView().scaleEffect(0.8) }
                        }
                        .font(.system(size: 14, weight: .medium))
                    }
                    .disabled(!canSubmit)
                } header: {
                    Text("第二步 · 输码确认")
                } footer: {
                    Text("认证器里看到的 6 位数字，30 秒换一次；同一个码不能重复用，报「验证码无效」时等下一轮再试。")
                        .font(.system(size: 11))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("启用两步验证")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { await loadSetup() }
    }

    private var canSubmit: Bool {
        !isSubmitting && normalizedCode.count == 6 && setup != nil
    }

    private func loadSetup() async {
        guard let client = session.client else {
            isLoading = false
            errorText = "未登录"
            return
        }
        do {
            setup = try await client.setupTwoFactor()
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    private func submit() async {
        guard let client = session.client else { return }
        isSubmitting = true
        errorText = nil
        do {
            let message = try await client.verifyTwoFactor(code: normalizedCode)
            onDone(message ?? "2FA 已启用")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isSubmitting = false
    }
}

/// 关闭流程：必须带当前动态码（`DELETE /security/2fa` + `{code}`）。
struct TwoFactorDisableView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let onDone: (String) -> Void

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    private var normalizedCode: String { code.filter { $0.isNumber } }

    var body: some View {
        List {
            Section {
                TextField("6 位动态码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
            } header: {
                Text("当前动态码")
            } footer: {
                Text("打开认证器应用，输入正在显示的 6 位数字。关闭成功后，下次登录就只需要密码。")
                    .font(.system(size: 11))
            }

            if let errorText {
                Section {
                    ErrorBanner(text: errorText)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await submit() }
                } label: {
                    HStack {
                        Image(systemName: "lock.open")
                        Text(isSubmitting ? "正在关闭…" : "确认关闭")
                        Spacer()
                        if isSubmitting { ProgressView().scaleEffect(0.8) }
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(isSubmitting || normalizedCode.count != 6)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关闭两步验证")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private func submit() async {
        guard let client = session.client else { return }
        isSubmitting = true
        errorText = nil
        do {
            let message = try await client.disableTwoFactor(code: normalizedCode)
            onDone(message ?? "2FA 已禁用")
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        isSubmitting = false
    }
}
