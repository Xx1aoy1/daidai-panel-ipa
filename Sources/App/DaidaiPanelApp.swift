import SwiftUI

@main
@MainActor
struct DaidaiPanelApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task { await session.restore() }
                .tint(AppTheme.accent)
        }
    }
}
