import SwiftUI
import UIKit

/// 系统分享面板。用来把下载到沙盒的原始日志交给「存储到文件 / 发给别人」。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 给 `.sheet(item:)` 用的包装：URL 本身不是 Identifiable。
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}
