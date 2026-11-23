import Foundation

// 系统设置（admin）与依赖管理（admin）的接口映射。
//
// 这两个模块的返回口径不统一，接入时逐条实测过：
//   GET /configs               → {data: {key: {...}}}，键是 map，值全是字符串
//   PUT /configs/batch         → {message}
//   GET /deps                  → {data: [...]}
//   POST /deps                 → 201 {message, data: [...]}（平级，不是包一层）
//   GET /deps/mirrors          → 裸对象，没有 data 外壳
//   GET /deps/export           → text/plain，一行一个包名
//   GET /deps/pip              → 裸数组 [{name, version}]
//   GET /deps/npm              → 裸对象 {dependencies: {...}}
//   GET /deps/playwright       → 裸对象
extension APIClient {

    // MARK: - 系统设置

    /// 只返回面板注册过的配置项，机器码、上次体检时间戳这类内部键不展示。
    func fetchConfigs() async throws -> [PanelConfigItem] {
        let data = try await send(path: "/configs")
        let map: [String: PanelConfigPayload] = try Self.decodeObject(data)
        return map.map { $0.value.toItem(key: $0.key) }
            .filter { $0.registered }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.key < rhs.key
            }
    }

    /// 单条写入。布尔传 "true"/"false"，数字传十进制字符串。
    @discardableResult
    func setConfig(key: String, value: String) async throws -> String? {
        let data = try await send(path: "/configs", method: "POST", json: ["key": key, "value": value])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 整组写入。网页端保存设置就是走这个，客户端也只提交改过的键。
    @discardableResult
    func setConfigs(_ values: [String: String]) async throws -> String? {
        let data = try await send(path: "/configs/batch", method: "PUT", json: ["configs": values])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - 依赖管理

    func fetchDependencies() async throws -> [PanelDependency] {
        let data = try await send(path: "/deps")
        if let envelope = try? Self.decoder.decode(DataEnvelope<[PanelDependency]>.self, from: data) {
            return envelope.data
        }
        return try Self.decoder.decode([PanelDependency].self, from: data)
    }

    /// 提交安装。面板会建记录并异步跑 pip / npm / apt，同名已存在的直接跳过。
    /// 名字里带 `; | & $ ( ) { }` 或以 `-` 开头会被面板静默丢弃，客户端先做一遍提示。
    @discardableResult
    func installDependencies(type: String,
                             names: [String],
                             pythonVersion: String? = nil) async throws -> DependencyInstallResult {
        var body: [String: Any] = ["type": type, "names": names]
        if let pythonVersion, !pythonVersion.isEmpty {
            body["python_version"] = pythonVersion
        }
        let data = try await send(path: "/deps", method: "POST", json: body)
        return (try? Self.decoder.decode(DependencyInstallResult.self, from: data))
            ?? DependencyInstallResult(message: nil, data: nil)
    }

    /// 单条状态 + 完整安装日志（列表接口不带 log）。
    func fetchDependency(id: Int) async throws -> PanelDependency {
        try await object("/deps/\(id)/status")
    }

    func deleteDependency(id: Int, force: Bool = false) async throws -> String? {
        let query = force ? ["force": "true"] : [:]
        let data = try await send(path: "/deps/\(id)", method: "DELETE", query: query)
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    func batchDeleteDependencies(ids: [Int]) async throws -> String? {
        let data = try await send(path: "/deps/batch-delete", method: "POST", json: ["ids": ids])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    func reinstallDependency(id: Int) async throws -> String? {
        let data = try await send(path: "/deps/\(id)/reinstall", method: "PUT")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 只能取消 installing / removing 中的任务，面板对其它状态回「当前依赖任务未在处理中」。
    func cancelDependency(id: Int) async throws -> String? {
        let data = try await send(path: "/deps/\(id)/cancel", method: "PUT")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    /// 导出清单：一行一个包名，Python 那份同时是合法的 requirements.txt。
    func exportDependencies(type: String, pythonVersion: String? = nil) async throws -> String {
        var query = ["type": type]
        if let pythonVersion, !pythonVersion.isEmpty { query["python_version"] = pythonVersion }
        let data = try await send(path: "/deps/export", query: query)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 镜像源

    func fetchDepMirrors() async throws -> DepMirrors {
        let data = try await send(path: "/deps/mirrors")
        return try Self.decoder.decode(DepMirrors.self, from: data)
    }

    /// 只提交非 nil 的字段：面板用指针判空，不传的镜像不会被改动。
    @discardableResult
    func setDepMirrors(pip: String? = nil, npm: String? = nil, linux: String? = nil) async throws -> String? {
        var body: [String: Any] = [:]
        if let pip { body["pip_mirror"] = pip }
        if let npm { body["npm_mirror"] = npm }
        if let linux { body["linux_mirror"] = linux }
        let data = try await send(path: "/deps/mirrors", method: "PUT", json: body)
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - Python 运行时

    func fetchPythonRuntimes() async throws -> PythonRuntimePayload {
        let data = try await send(path: "/deps/python-runtimes")
        return try Self.decodeObject(data)
    }

    @discardableResult
    func setDefaultPythonRuntime(version: String) async throws -> String? {
        let data = try await send(path: "/deps/python-runtime-default",
                                  method: "PUT",
                                  json: ["version": version])
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }

    // MARK: - 已装包清单

    /// `python_version` 缺省时面板用自己的默认版本。
    func fetchPipPackages(pythonVersion: String? = nil) async throws -> [PipPackage] {
        var query: [String: String] = [:]
        if let pythonVersion, !pythonVersion.isEmpty { query["python_version"] = pythonVersion }
        let data = try await send(path: "/deps/pip", query: query)
        if let items = try? Self.decoder.decode([PipPackage].self, from: data) {
            return items
        }
        if let envelope = try? Self.decoder.decode(DataEnvelope<[PipPackage]>.self, from: data) {
            return envelope.data
        }
        throw PanelError.decoding("pip 列表解析失败")
    }

    func fetchNpmPackages() async throws -> [NpmPackage] {
        let data = try await send(path: "/deps/npm")
        let list = try Self.decoder.decode(NpmPackageList.self, from: data)
        return list.items
    }

    // MARK: - Playwright

    func fetchPlaywrightStatus() async throws -> PlaywrightStatus {
        let data = try await send(path: "/deps/playwright")
        return try Self.decoder.decode(PlaywrightStatus.self, from: data)
    }

    /// 一键安装会把系统依赖（几十个包）+ Chromium 排进顺序队列，可能要跑很久。
    @discardableResult
    func installPlaywright() async throws -> String? {
        let data = try await send(path: "/deps/playwright/install", method: "POST")
        return (try? Self.decoder.decode(MessagePayload.self, from: data))?.message
    }
}
