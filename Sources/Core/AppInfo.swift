import Foundation
import UIKit

enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 只用于请求头，必须是 ASCII，所以取 "iPhone" / "iPad" 这种固定值。
    static var deviceModel: String {
        UIDevice.current.model
    }

    static var systemVersion: String {
        UIDevice.current.systemVersion
    }

    static var deviceName: String {
        UIDevice.current.name
    }
}

extension Notification.Name {
    static let panelSessionExpired = Notification.Name("panelSessionExpired")
}
