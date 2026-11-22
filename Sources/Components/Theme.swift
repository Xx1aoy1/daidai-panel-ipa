import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.24, green: 0.47, blue: 0.96)
    static let accentSoft = Color(red: 0.24, green: 0.47, blue: 0.96).opacity(0.12)
    static let success = Color(red: 0.13, green: 0.62, blue: 0.42)
    static let failure = Color(red: 0.85, green: 0.26, blue: 0.28)
    static let warning = Color(red: 0.93, green: 0.60, blue: 0.13)
    static let running = Color(red: 0.20, green: 0.52, blue: 0.95)
    static let idle = Color(red: 0.45, green: 0.48, blue: 0.55)
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let pageBackground = Color(UIColor.systemGroupedBackground)
}

extension View {
    /// 卡片式容器背景。
    func cardStyle(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
