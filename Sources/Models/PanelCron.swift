import Foundation

/// `GET /tasks/cron/templates` 的元素。面板自己维护分类模板，
/// 表达式可能是 5 位（标准）也可能是 6 位（带秒），客户端只负责原样展示与填充。
struct CronTemplate: Decodable, Identifiable, Equatable {
    var name: String?
    var expression: String?
    var category: String?
    var description: String?

    var id: String { "\(category ?? "")|\(expression ?? "")|\(name ?? "")" }
    var title: String { name ?? expression ?? "模板" }
    var categoryName: String { (category?.isEmpty == false) ? category! : "常用" }
    var expressionText: String { expression ?? "" }
}

/// `POST /tasks/cron/parse` 的返回：面板会把表达式翻译成中文，并给出接下来几次执行时间。
struct CronParseResult: Decodable {
    var isValid: Bool?
    var description: String?
    var format: String?
    var nextRunTimes: [String]?

    var valid: Bool { isValid ?? false }
    var descriptionText: String { description ?? "" }
    var formatText: String { format ?? "" }

    var nextRunDates: [Date] {
        (nextRunTimes ?? []).compactMap { DateParser.parse($0) }
    }
}
