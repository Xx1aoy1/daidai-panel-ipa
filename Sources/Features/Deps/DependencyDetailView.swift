import SwiftUI
import UIKit

/// 依赖详情：状态 + 完整安装日志 + 重装/取消/卸载。
/// 安装中的记录每 1.5 秒拉一次 `GET /deps/:id/status`（这个接口带 log，列表接口不带）。
struct DependencyDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var dep: PanelDependency
    @State private var errorText: String?
    @State private var actionBusy = false
    @State private var toast: String?
    @State private var timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    let onChanged: () -> Void

    init(dependency: PanelDependency, onChanged: @escaping () -> Void) {
        _dep = State(initialValue: dependency)
        self.onChanged = onChanged
    }

    private var statusColor: Color {
        switch dep.status {
        case "installed": return AppTheme.success
        case "installing", "queued": return AppTheme.running
        case "removing": return AppTheme.warning
        case "failed": return AppTheme.failure
        default: return AppTheme.idle
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorText {
                ErrorBanner(text: errorText)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: dep.typeIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(dep.name)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    StatusBadge(text: dep.statusText, color: statusColor)
                }

                KeyValueRow(label: "类型", value: dep.typeText)
                if let badge = dep.versionBadge {
                    KeyValueRow(label: "版本", value: badge)
                }
                KeyValueRow(label: "记录 ID", value: "\(dep.id)", monospaced: true)
                KeyValueRow(label: "创建", value: DateText.relative(dep.createdAt))
                KeyValueRow(label: "更新", value: DateText.relative(dep.updatedAt))

                HStack(spacing: 8) {
                    if dep.isBusy {
                        Button {
                            Task { await cancel() }
                        } label: {
                            Label("取消安装", systemImage: "stop.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.warning)
                    } else {
                        Button {
                            Task { await reinstall() }
                        } label: {
                            Label("重新安装", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent)
                    }

                    Button(role: .destructive) {
                        Task { await remove(force: false) }
                    } label: {
                        Label("卸载", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.failure)
                    .disabled(dep.isBusy)

                    if actionBusy {
                        ProgressView().scaleEffect(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HStack(spacing: 6) {
                Text("安装日志")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                if dep.isBusy {
                    Text("实时刷新中")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.running)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = dep.log ?? ""
                    flash("日志已复制")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled((dep.log ?? "").isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            logView
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(dep.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await remove(force: true) }
                    } label: {
                        Label("强制卸载（只删记录 + 强删文件）", systemImage: "trash.slash")
                    }
                    .disabled(dep.isBusy)
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("刷新日志", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    Button("关闭") { dismiss() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await reload() }
        .onReceive(timer) { _ in
            guard dep.isBusy else { return }
            Task { await reload(silent: true) }
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

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let log = dep.log, !log.isEmpty {
                    Text(log)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("log-bottom")
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(dep.isBusy ? "安装刚开始，还没有输出" : "这条记录没有日志")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .onChange(of: dep.log) { _ in
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - 动作

    private func reload(silent: Bool = false) async {
        guard let client = session.client else { return }
        do {
            dep = try await client.fetchDependency(id: dep.id)
            if !silent { errorText = nil }
        } catch {
            if !silent {
                errorText = (error as? PanelError)?.message ?? error.localizedDescription
            }
        }
    }

    private func reinstall() async {
        guard let client = session.client else { return }
        actionBusy = true
        do {
            let message = try await client.reinstallDependency(id: dep.id)
            flash(message ?? "正在重新安装")
            dep.status = "installing"
            dep.log = ""
            onChanged()
            await reload(silent: true)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        actionBusy = false
    }

    private func cancel() async {
        guard let client = session.client else { return }
        actionBusy = true
        do {
            let message = try await client.cancelDependency(id: dep.id)
            flash(message ?? "已提交取消请求")
            await reload(silent: true)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
        }
        actionBusy = false
    }

    private func remove(force: Bool) async {
        guard let client = session.client else { return }
        actionBusy = true
        do {
            let message = try await client.deleteDependency(id: dep.id, force: force)
            flash(message ?? "已提交卸载")
            onChanged()
            actionBusy = false
            if force {
                dismiss()
                return
            }
            dep.status = "removing"
            await reload(silent: true)
        } catch {
            errorText = (error as? PanelError)?.message ?? error.localizedDescription
            actionBusy = false
        }
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}
