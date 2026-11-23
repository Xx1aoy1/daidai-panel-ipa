import SwiftUI
import UIKit

/// 脚本试跑结果面板：启动一次运行并跟随输出。
/// 面板在运行结束后**不会**清空 `/scripts/run/:id/logs`，所以这里可以原地保留完整输出。
struct ScriptRunView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.presentationMode) private var presentationMode

    let title: String
    let source: ScriptRunner.Source

    @StateObject private var runner = ScriptRunner()
    @State private var follow = true

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                Divider()
                output
            }
            .background(Color(UIColor.systemBackground).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        runner.stopPolling()
                        if let client = session.client { runner.cleanup(client: client) }
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = runner.lines.joined(separator: "\n")
                        } label: {
                            Label("复制全部输出", systemImage: "doc.on.doc")
                        }
                        Button {
                            follow.toggle()
                        } label: {
                            Label(follow ? "暂停自动滚动" : "恢复自动滚动",
                                  systemImage: follow ? "pause.circle" : "arrow.down.to.line.compact")
                        }
                        if runner.isRunning, let client = session.client {
                            Divider()
                            Button(role: .destructive) {
                                runner.requestStop(client: client)
                            } label: {
                                Label("终止运行", systemImage: "stop.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: start)
        .onDisappear { runner.stopPolling() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(runner.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if let exitCode = runner.exitCode {
                Text("· 退出码 \(exitCode)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if runner.isRunning {
                ProgressView().scaleEffect(0.6)
            }

            Text("\(runner.lines.count) 行")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.pageBackground)
        .overlay(alignment: .bottomLeading) {
            if let errorMessage = runner.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.failure)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
                    .lineLimit(1)
            }
        }
    }

    private var statusColor: Color {
        if runner.isRunning { return AppTheme.running }
        if runner.isDone { return runner.isSuccess ? AppTheme.success : AppTheme.failure }
        return AppTheme.idle
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if runner.lines.isEmpty {
                        EmptyStateView(icon: "terminal",
                                       title: runner.isRunning ? "等待输出…" : "没有输出",
                                       message: runner.isRunning ? "脚本已启动，正在捕获标准输出" : "这次运行没有产生任何内容")
                    } else {
                        ForEach(Array(runner.lines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(lineColor(line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: runner.lines.count) { _ in
                guard follow else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    /// 面板在日志末尾追加的「[进程结束, 退出码: n]」用灰色弱化，失败行标红，方便扫读。
    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("[进程结束") { return .secondary }
        let lowered = line.lowercased()
        if lowered.contains("traceback") || lowered.contains("error") || lowered.contains("exception") {
            return AppTheme.failure
        }
        return .primary
    }

    private func start() {
        guard let client = session.client else { return }
        runner.start(client: client, source: source)
    }
}
