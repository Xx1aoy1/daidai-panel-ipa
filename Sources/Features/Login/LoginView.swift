import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var totp = ""
    @State private var serverName = ""
    @State private var needsTotp = false
    @State private var showPassword = false
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case address, username, password, totp, name
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    loginCard
                    if !session.servers.isEmpty { savedServers }
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 46)
                .padding(.bottom, 30)
            }
        }
    }

    // MARK: - 组件

    private var header: some View {
        VStack(spacing: 12) {
            AppLogo(size: 78)
            Text("呆呆面板")
                .font(.system(size: 24, weight: .bold))
            Text("连接你的定时任务面板")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var loginCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                InputRow(icon: "server.rack",
                         placeholder: "服务器地址，如 192.168.0.100:5700",
                         text: $address,
                         keyboard: .URL)
                    .focused($focused, equals: .address)
                    .submitLabel(.next)
                    .onSubmit { focused = .username }

                Divider().padding(.leading, 38)

                InputRow(icon: "person",
                         placeholder: "用户名",
                         text: $username)
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }

                Divider().padding(.leading, 38)

                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 18)

                    Group {
                        if showPassword {
                            TextField("密码", text: $password)
                        } else {
                            SecureField("密码", text: $password)
                        }
                    }
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)

                if needsTotp {
                    Divider().padding(.leading, 38)

                    InputRow(icon: "number.square",
                             placeholder: "两步验证码（6 位）",
                             text: $totp,
                             keyboard: .numberPad)
                        .focused($focused, equals: .totp)
                }
            }
            .padding(.horizontal, 12)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorText {
                ErrorBanner(text: errorText)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    }
                    Text(isBusy ? "连接中…" : "连接面板")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(isBusy ? 0.75 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Text("地址支持 http / https；填 IP:端口 时默认按 http 连接。登录凭证只保存在本机 Keychain。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
    }

    private var savedServers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已保存的面板")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(session.servers.enumerated()), id: \.element.id) { index, server in
                    Button {
                        fill(with: server)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.displayName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("\(server.baseURL) · \(server.username)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await session.removeServer(server) }
                        } label: {
                            Label("删除该面板", systemImage: "trash")
                        }
                    }

                    if index < session.servers.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("适配呆呆面板 v3.x · 开源客户端")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("版本 \(AppInfo.version)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.top, 8)
    }

    // MARK: - 行为

    private func fill(with server: PanelServer) {
        address = server.baseURL
        username = server.username
        serverName = server.name
        password = ""
        totp = ""
        needsTotp = false
        errorText = nil
        focused = .password
    }

    private func submit() {
        guard !isBusy else { return }
        focused = nil

        let normalized = PanelServer.normalize(address)
        guard let url = URL(string: normalized), url.host != nil else {
            errorText = "地址格式不对，示例：192.168.0.100:5700"
            return
        }
        guard !username.isEmpty else {
            errorText = "请填写用户名"
            return
        }
        guard !password.isEmpty else {
            errorText = "请填写密码"
            return
        }
        if needsTotp && totp.trimmingCharacters(in: .whitespaces).isEmpty {
            errorText = "请填写两步验证码"
            return
        }

        isBusy = true
        errorText = nil

        Task {
            do {
                let server = PanelServer(name: serverName, baseURL: normalized, username: username)
                try await session.login(server: server,
                                        password: password,
                                        totp: needsTotp ? totp : nil)
            } catch let error as PanelError {
                handle(error)
            } catch {
                errorText = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func handle(_ error: PanelError) {
        switch error.code {
        case "two_factor_required":
            needsTotp = true
            errorText = "该账号已开启两步验证，请补充 6 位动态码"
            focused = .totp
        case "invalid_totp":
            needsTotp = true
            errorText = "两步验证码不正确"
            focused = .totp
        case "captcha_required":
            errorText = "面板开启了人机验证，请先在网页端登录一次，再回 App 重试"
        default:
            errorText = error.message
        }
    }
}

private struct InputRow: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(.vertical, 12)
    }
}
