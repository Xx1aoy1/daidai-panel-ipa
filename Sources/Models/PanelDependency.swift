import Foundation

/// `GET /deps` 的一项托管依赖。
///
/// 面板把「装了什么」记在自己的表里（`dependencies`），状态机是：
/// queued → installing → installed / failed，卸载时走 removing，取消后是 cancelled。
/// Python 依赖会带 `python_version`（3.10 / 3.11 / 3.12），nodejs 与 linux 为空。
/// `log` 只有 `GET /deps/:id/status` 返回，列表接口不带。
struct PanelDependency: Decodable, Identifiable, Equatable {
    let id: Int
    var name: String
    var type: String
    var status: String
    var pythonVersion: String?
    var createdAt: String?
    var updatedAt: String?
    var log: String?

    var typeText: String {
        switch type {
        case "python": return "Python"
        case "linux": return "系统包"
        default: return "Node.js"
        }
    }

    var typeIcon: String {
        switch type {
        case "python": return "chevron.left.forwardslash.chevron.right"
        case "linux": return "terminal.fill"
        default: return "shippingbox.fill"
        }
    }

    /// 面板的状态值是英文枚举，这里是给列表用的中文标签。
    var statusText: String {
        switch status {
        case "installed": return "已安装"
        case "installing": return "安装中"
        case "queued": return "排队中"
        case "removing": return "卸载中"
        case "failed": return "失败"
        case "cancelled": return "已取消"
        default: return status
        }
    }

    /// 这三种状态面板会拒绝删除/重装（回「依赖正在处理中」），客户端先挡掉。
    var isBusy: Bool {
        ["queued", "installing", "removing"].contains(status)
    }

    var isFailed: Bool { status == "failed" }

    var isInstalled: Bool { status == "installed" }

    /// Python 依赖在列表里标出版本，否则同一个包在三个版本下看不出来区别。
    var versionBadge: String? {
        guard type == "python", let pythonVersion, !pythonVersion.isEmpty else { return nil }
        return "Py \(pythonVersion)"
    }

    var subtitle: String {
        var parts = [typeText]
        if let badge = versionBadge { parts.append(badge) }
        if let updatedAt { parts.append("更新于 \(DateText.relative(updatedAt))") }
        return parts.joined(separator: " · ")
    }
}

/// `POST /deps` 的 201 回执：`{message, data: [...]}`（message 与 data 平级）。
struct DependencyInstallResult: Decodable {
    var message: String?
    var data: [PanelDependency]?
}

/// `GET /deps/mirrors`：**没有 data 外壳**，直接是镜像配置。
struct DepMirrors: Decodable, Equatable {
    var linuxDistribution: String?
    var linuxMirror: String?
    var linuxMirrorLabel: String?
    var linuxMirrorMessage: String?
    var linuxMirrorSupported: Bool?
    var linuxPackageManager: String?
    var npmMirror: String?
    var pipMirror: String?

    var packageManagerText: String {
        let manager = (linuxPackageManager ?? "").isEmpty ? "apt" : (linuxPackageManager ?? "")
        let distro = (linuxDistribution ?? "").isEmpty ? "" : " · \(linuxDistribution ?? "")"
        return manager + distro
    }
}

/// `GET /deps/python-runtimes`：`{data: [...], default_version: "3.12"}`。
struct PythonRuntimePayload: Decodable {
    var data: [PythonRuntime]
    var defaultVersion: String?
}

struct PythonRuntime: Decodable, Identifiable, Equatable {
    var version: String
    var label: String?
    var isDefault: Bool?
    var venvPath: String?
    var venvHealthy: Bool?
    var pythonPath: String?
    var pipPath: String?
    var available: Bool?
    var message: String?

    var id: String { version }

    var title: String {
        if let label, !label.isEmpty { return label }
        return "Python \(version)"
    }

    var isHealthy: Bool { (venvHealthy ?? false) && (available ?? true) }

    /// 面板字段名就是 `default`，和驼峰转换对不上，单独映射。
    private enum CodingKeys: String, CodingKey {
        case version
        case label
        case isDefault = "default"
        case venvPath
        case venvHealthy
        case pythonPath
        case pipPath
        case available
        case message
    }
}

/// `GET /deps/pip`：裸数组 `[{name, version}]`。
struct PipPackage: Decodable, Identifiable, Equatable {
    var name: String
    var version: String?

    var id: String { name }
}

/// `GET /deps/npm`：`{name, dependencies: {包名: {version, overridden}}}`。
struct NpmPackageList: Decodable {
    var name: String?
    var dependencies: [String: NpmPackageInfo]?

    var items: [NpmPackage] {
        (dependencies ?? [:]).map { NpmPackage(name: $0.key, version: $0.value.version, overridden: $0.value.overridden ?? false) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct NpmPackageInfo: Decodable {
    var version: String?
    var overridden: Bool?
}

struct NpmPackage: Identifiable, Equatable {
    var name: String
    var version: String?
    var overridden: Bool

    var id: String { name }
}

/// `GET /deps/playwright`：Playwright 运行环境体检结果。
///
/// `linux_installed / linux_total` 是系统依赖包的安装进度，
/// `browsers_installed` 是 Chromium 是否已下到数据卷。
struct PlaywrightStatus: Decodable {
    var supported: Bool?
    var reason: String?
    var distribution: String?
    var versionId: String?
    var arch: String?
    var packages: [String]?
    var browsersPath: String?
    var pythonInstalled: Bool?
    var browsersInstalled: Bool?
    var linuxInstalled: Int?
    var linuxTotal: Int?

    var isSupported: Bool { supported ?? false }

    var linuxText: String {
        "\(linuxInstalled ?? 0)/\(linuxTotal ?? 0)"
    }

    var linuxFraction: Double {
        guard let total = linuxTotal, total > 0 else { return 0 }
        return min(max(Double(linuxInstalled ?? 0) / Double(total), 0), 1)
    }

    /// 三项都齐了才算装好。
    var isReady: Bool {
        (pythonInstalled ?? false) && (browsersInstalled ?? false)
    }
}
