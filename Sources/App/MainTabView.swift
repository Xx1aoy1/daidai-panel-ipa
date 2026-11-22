import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("概览", systemImage: "gauge") }
                .tag(0)

            TaskListView()
                .tabItem { Label("任务", systemImage: "list.bullet.rectangle") }
                .tag(1)

            LogListView()
                .tabItem { Label("日志", systemImage: "doc.text.magnifyingglass") }
                .tag(2)

            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis.circle") }
                .tag(3)
        }
        .overlay(alignment: .top) {
            if let message = session.sessionMessage {
                SessionBanner(message: message)
            }
        }
    }
}

private struct SessionBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.failure)
        .clipShape(Capsule())
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
