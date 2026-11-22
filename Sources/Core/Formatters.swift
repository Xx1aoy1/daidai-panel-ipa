import Foundation

enum DateParser {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let plainFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let plainNoSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let date = isoWithFraction.date(from: text) { return date }
        if let date = isoPlain.date(from: text) { return date }
        if text.hasSuffix("Z") { text.removeLast() }
        if let date = plainFormatter.date(from: text) { return date }
        if let date = plainNoSeconds.date(from: text) { return date }
        return nil
    }
}

enum DateText {
    static func relative(_ raw: String?) -> String {
        guard let date = DateParser.parse(raw) else { return "—" }
        return relative(date)
    }

    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 0 { return "刚刚" }
        if interval < 60 { return "\(Int(interval)) 秒前" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400)) 天前" }
        return absolute(date)
    }

    static func absolute(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func total(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
