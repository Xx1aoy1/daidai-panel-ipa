import Foundation

/// `GET /configs` 里的一项系统设置。
///
/// 这个接口返回的是 **map**（键 = 配置键名），而且**所有值都是字符串**：
/// 布尔是 `"true"` / `"false"`，数字是 `"5"`，枚举是枚举值本身。
/// `value_type` / `min` / `max` / `options` 用来决定渲染什么控件，
/// `registered == false` 的是面板内部键（机器码、上次体检时间戳），设置页不展示。
struct PanelConfigItem: Identifiable, Equatable {
    let key: String
    var label: String?
    var detail: String?
    var group: String
    var groupLabel: String
    var order: Int
    var valueType: String
    var secret: Bool
    var registered: Bool
    var value: String
    var defaultValue: String?
    var minValue: Double?
    var maxValue: Double?
    var options: [ConfigOption]
    var updatedAt: String?

    var id: String { key }

    var title: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return key
    }

    var groupTitle: String {
        groupLabel.isEmpty ? group : groupLabel
    }

    var kind: ConfigKind {
        if secret { return .secret }
        switch valueType {
        case "bool": return .flag
        case "int": return .number
        case "enum": return .choice
        default: return isMultiline ? .multiline : .text
        }
    }

    /// 换行 / 逗号分隔的清单类配置，用多行输入更好改。
    var isMultiline: Bool {
        key == "trusted_proxy_cidrs"
            || key == "backup_schedule_selection"
            || key == "repo_file_extensions"
            || key == "random_delay_extensions"
    }

    /// `*_at` 是面板自己写的时间戳，改成别的值只会让「上次更新时间」变得荒诞，这里只读展示。
    var isReadOnly: Bool { key.hasSuffix("_at") }

    /// 数字项的范围提示，例如 `范围 1–100`。
    var rangeHint: String? {
        guard kind == .number else { return nil }
        switch (minValue, maxValue) {
        case let (min?, max?): return "范围 \(Self.trimZero(min))–\(Self.trimZero(max))"
        case let (min?, nil): return "不小于 \(Self.trimZero(min))"
        case let (nil, max?): return "不大于 \(Self.trimZero(max))"
        default: return nil
        }
    }

    /// 字节类配置补一句人话，102400000 这种数字光看没法判断。
    var valueHint: String? {
        guard key.contains("size"), let bytes = Double(value), bytes > 0 else { return nil }
        return "约 \(Bytes.text(bytes))"
    }

    var readOnlyText: String {
        guard key.hasSuffix("_at") else { return value }
        guard let date = DateParser.parse(value) else { return value }
        return "\(DateText.relative(date))（\(DateText.absolute(date))）"
    }

    private static func trimZero(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(value)
    }
}

enum ConfigKind: Equatable {
    case flag
    case number
    case choice
    case text
    case multiline
    case secret
}

struct ConfigOption: Decodable, Identifiable, Equatable {
    var value: String
    var label: String

    var id: String { value }

    /// 面板偶尔只给 label 不给 value，这里兜一下，避免选项全变成同一个 id。
    private enum CodingKeys: String, CodingKey {
        case value
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try? container.decode(AnyString.self, forKey: .value)
        let rawLabel = try? container.decode(AnyString.self, forKey: .label)
        value = rawValue?.value ?? rawLabel?.value ?? ""
        label = rawLabel?.value ?? value
    }
}

/// `/configs` 的原始单项。字段全是可选的：未注册的键没有 label / group / value_type。
struct PanelConfigPayload: Decodable {
    var label: String?
    var detail: String?
    var group: String?
    var groupLabel: String?
    var order: Int?
    var valueType: String?
    var secret: Bool?
    var registered: Bool?
    var value: AnyString?
    var defaultValue: AnyString?
    var min: Double?
    var max: Double?
    var options: [ConfigOption]?
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case label
        case detail = "description"
        case group
        case groupLabel
        case order
        case valueType
        case secret
        case registered
        case value
        case defaultValue
        case min
        case max
        case options
        case updatedAt
    }

    func toItem(key: String) -> PanelConfigItem {
        PanelConfigItem(key: key,
                        label: label,
                        detail: (detail?.isEmpty ?? true) ? nil : detail,
                        group: group ?? "",
                        groupLabel: groupLabel ?? "",
                        order: order ?? 9999,
                        valueType: valueType ?? "string",
                        secret: secret ?? false,
                        registered: registered ?? false,
                        value: value?.value ?? "",
                        defaultValue: defaultValue?.value,
                        minValue: min,
                        maxValue: max,
                        options: options ?? [],
                        updatedAt: updatedAt)
    }
}

/// 面板的配置值理论上都是字符串，但历史数据里混进过数字/布尔，
/// 用这个包装统一转成字符串，避免某一条脏数据让整页解析失败。
struct AnyString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let flag = try? container.decode(Bool.self) {
            value = flag ? "true" : "false"
        } else if let number = try? container.decode(Int.self) {
            value = "\(number)"
        } else if let number = try? container.decode(Double.self) {
            value = "\(number)"
        } else {
            value = ""
        }
    }

    init(_ value: String) {
        self.value = value
    }
}

/// 设置页按组渲染用。组的顺序取组内最小 order，和网页端的注册顺序一致。
struct ConfigSection: Identifiable {
    let id: String
    let title: String
    let note: String?
    var items: [PanelConfigItem]

    /// 组图标按 group key 映射，面板没提供图标字段。
    var systemImage: String {
        switch id {
        case "tasks": return "gearshape.2.fill"
        case "network": return "network"
        case "alerts": return "exclamationmark.bubble.fill"
        case "subscription": return "arrow.triangle.2.circlepath"
        case "security": return "lock.shield.fill"
        case "branding": return "paintbrush.fill"
        case "backup": return "externaldrive.fill"
        default: return "slider.horizontal.3"
        }
    }

    static let notes: [String: String] = [
        "tasks": "并发数与日志保留对全局面板生效，保存后立即应用，不需要重启。",
        "network": "代理与镜像用于面板拉取更新、订阅和构建依赖。GitHub Token 只存在面板本机。",
        "alerts": "资源占用超过阈值时，通过「通知渠道」里启用的渠道推送到手机。",
        "subscription": "订阅拉取后的默认行为，单个订阅可以覆盖这里的设置。",
        "security": "会话数上限会影响本机是否被挤下线；验证码开启后网页端登录需要填验证码。",
        "branding": "面板标题、时区与外观。",
        "backup": "定时备份会打包所选数据，可加密码加密。"
    ]

    static func build(from items: [PanelConfigItem]) -> [ConfigSection] {
        var buckets: [String: [PanelConfigItem]] = [:]
        for item in items {
            let key = item.group.isEmpty ? "other" : item.group
            buckets[key, default: []].append(item)
        }
        return buckets
            .map { key, list in
                ConfigSection(id: key,
                              title: list.first?.groupTitle ?? key,
                              note: notes[key],
                              items: list.sorted { lhs, rhs in
                                  if lhs.order != rhs.order { return lhs.order < rhs.order }
                                  return lhs.key < rhs.key
                              })
            }
            .sorted { lhs, rhs in
                let left = lhs.items.first?.order ?? 9999
                let right = rhs.items.first?.order ?? 9999
                if left != right { return left < right }
                return lhs.id < rhs.id
            }
    }
}
