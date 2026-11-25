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
        // Go 的 time.Time 序列化出来是 9 位纳秒（2026-11-23T19:32:12.433947741+08:00），
        // 而 /system/processes 的 started_at 只有 2 位（2026-11-22T20:25:28.99+08:00）。
        // ISO8601DateFormatter 对非 3 位小数不稳，统一补齐/裁到 3 位再试。
        let normalized = normalizeFraction(text)
        if normalized != text, let date = isoWithFraction.date(from: normalized) { return date }
        if text.hasSuffix("Z") { text.removeLast() }
        if let date = plainFormatter.date(from: text) { return date }
        if let date = plainNoSeconds.date(from: text) { return date }
        let shortenedPlain = normalizeFraction(text)
        if shortenedPlain != text, let date = plainFormatter.date(from: shortenedPlain) { return date }
        return nil
    }

    /// 把小数秒统一成 3 位：多了裁掉，少了补 0。没有小数部分时原样返回。
    private static func normalizeFraction(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }
        var index = text.index(after: dot)
        var digits = 0
        while index < text.endIndex, text[index].isNumber {
            index = text.index(after: index)
            digits += 1
        }
        guard digits > 0 else { return text }
        let tail = String(text[index...])
        let fraction = String(text[text.index(after: dot)..<index])

        if digits == 3 { return text }
        if digits > 3 {
            let keep = fraction.prefix(3)
            return String(text[text.startIndex..<dot]) + "." + keep + tail
        }
        let padded = fraction + String(repeating: "0", count: 3 - digits)
        return String(text[text.startIndex..<dot]) + "." + padded + tail
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

    /// 只要时分秒，用于「更新于 12:34:56」这类实时刷新的脚注。
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
