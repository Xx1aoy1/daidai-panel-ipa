import SwiftUI

struct StatusBadge: View {
    let text: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .foregroundColor(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var tint: Color = AppTheme.accent
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 12)
    }
}

struct SectionCard<Content: View>: View {
    let title: String?
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 5) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.failure)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.failure)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.failure.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundColor(valueColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct LoadingHint: View {
    var text: String = "加载中…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
