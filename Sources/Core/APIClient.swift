import Foundation
import UIKit

/// 面板 HTTP 客户端：负责拼地址、带鉴权头、401 自动用 refresh token 续期。
/// 所有方法都在主线程 actor 上，网络请求本身是挂起而非阻塞。
@MainActor
final class APIClient {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    let rootURL: URL
    private let apiBaseString: String
    private let session: URLSession
    private let streamSession: URLSession

    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    /// 续期成功后回调，用于把新 token 写回 Keychain。
    var onTokensChanged: ((_ access: String?, _ refresh: String?) -> Void)?

    init(rootURL: URL, accessToken: String?, refreshToken: String?) {
        var root = rootURL.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        self.rootURL = URL(string: root) ?? rootURL
        self.apiBaseString = root + "/api/v1"
        self.accessToken = accessToken
        self.refreshToken = refreshToken

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)

        let streamConfiguration = URLSessionConfiguration.default
        streamConfiguration.timeoutIntervalForRequest = 3600
        streamConfiguration.timeoutIntervalForResource = 7200
        self.streamSession = URLSession(configuration: streamConfiguration)
    }

    func updateTokens(access: String?, refresh: String? = nil) {
        accessToken = access
        if let refresh { refreshToken = refresh }
    }

    /// 登录成功后写入两枚令牌（setter 只在类内可见，所以由这里代写）。
    func storeTokens(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }

    // MARK: - 地址与请求构造

    private func url(path: String, query: [String: String]) throws -> URL {
        var base = apiBaseString
        if !path.hasPrefix("/") { base += "/" }
        base += path
        guard var components = URLComponents(string: base) else { throw PanelError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw PanelError.invalidURL }
        return url
    }

    private func applyClientHeaders(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 面板按这几个头把会话识别成「APP 端」，从而走 APP 端会话数上限，不会挤掉网页登录。
        request.setValue("app", forHTTPHeaderField: "X-Client-Type")
        request.setValue("DaidaiPanel-iOS", forHTTPHeaderField: "X-Client-App")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(AppInfo.deviceModel, forHTTPHeaderField: "X-Device-Model")
        request.setValue(AppInfo.systemVersion, forHTTPHeaderField: "X-OS-Version")
        request.setValue("DaidaiPanel-iOS/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
    }

    private func makeRequest(path: String,
                             method: String,
                             query: [String: String],
                             json: Any?,
                             authorized: Bool) throws -> URLRequest {
        let target = try url(path: path, query: query)
        var request = URLRequest(url: target)
        request.httpMethod = method
        applyClientHeaders(&request)
        if authorized, let token = accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])
        }
        return request
    }

    // MARK: - 执行

    private func execute(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PanelError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PanelError.transport("服务器没有返回有效响应")
        }
        if (200..<300).contains(http.statusCode) { return data }

        let body = try? Self.decoder.decode(APIErrorBody.self, from: data)
        if http.statusCode == 401 {
            throw PanelError.unauthorized(message: body?.error, code: body?.code)
        }
        let message = body?.error ?? "请求失败（HTTP \(http.statusCode)）"
        throw PanelError.server(status: http.statusCode, message: message, code: body?.code)
    }

    @discardableResult
    func send(path: String,
              method: String = "GET",
              query: [String: String] = [:],
              json: Any? = nil,
              authorized: Bool = true,
              canRefresh: Bool = true) async throws -> Data {
        let request = try makeRequest(path: path, method: method, query: query, json: json, authorized: authorized)
        do {
            return try await execute(request)
        } catch let error as PanelError {
            guard canRefresh, authorized, error.isAuthExpired else { throw error }
            let freshToken = try await refreshAccessToken()
            var retry = request
            retry.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            return try await execute(retry)
        }
    }

    // MARK: - 续期

    func refreshAccessToken() async throws -> String {
        guard let refresh = refreshToken, !refresh.isEmpty else { throw PanelError.sessionExpired }
        var request = try makeRequest(path: "/auth/refresh", method: "POST", query: [:], json: nil, authorized: false)
        request.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")

        let data: Data
        do {
            data = try await execute(request)
        } catch {
            throw PanelError.sessionExpired
        }

        let payload: RefreshPayload? = (try? Self.decoder.decode(RefreshPayload.self, from: data))
            ?? ((try? Self.decoder.decode(DataEnvelope<RefreshPayload>.self, from: data))?.data)
        guard let token = payload?.accessToken, !token.isEmpty else { throw PanelError.sessionExpired }

        accessToken = token
        onTokensChanged?(token, refreshToken)
        return token
    }

    // MARK: - 解码

    static func decodeObject<T: Decodable>(_ data: Data) throws -> T {
        if let envelope = try? decoder.decode(DataEnvelope<T>.self, from: data) {
            return envelope.data
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PanelError.decoding(detail(of: error))
        }
    }

    static func detail(of error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, _):
                return "缺少字段 \(key.stringValue)"
            case .typeMismatch(_, let context):
                return "字段类型不匹配：\(context.debugDescription)"
            case .valueNotFound(_, let context):
                return "字段为空：\(context.debugDescription)"
            case .dataCorrupted(let context):
                return "数据损坏：\(context.debugDescription)"
            @unknown default:
                return "\(decodingError)"
            }
        }
        return error.localizedDescription
    }

    func object<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await send(path: path, query: query)
        return try Self.decodeObject(data)
    }

    func list<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> PagedResult<T> {
        let data = try await send(path: path, query: query)
        if let paged = try? Self.decoder.decode(PagedEnvelope<T>.self, from: data) {
            let items = paged.data ?? []
            return PagedResult(items: items,
                               total: paged.total ?? items.count,
                               page: paged.page ?? 1,
                               pageSize: paged.pageSize ?? items.count)
        }
        if let envelope = try? Self.decoder.decode(DataEnvelope<[T]>.self, from: data) {
            return PagedResult(items: envelope.data,
                               total: envelope.data.count,
                               page: 1,
                               pageSize: envelope.data.count)
        }
        if let items = try? Self.decoder.decode([T].self, from: data) {
            return PagedResult(items: items, total: items.count, page: 1, pageSize: items.count)
        }
        throw PanelError.decoding("列表解析失败")
    }

    // MARK: - 流式请求（SSE 日志）

    func streamRequest(path: String, query: [String: String] = [:]) throws -> URLRequest {
        var request = try makeRequest(path: path, method: "GET", query: query, json: nil, authorized: true)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 3600
        return request
    }

    func streamBytes(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        let (bytes, response) = try await streamSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 401 { throw PanelError.sessionExpired }
            throw PanelError.transport("日志流连接失败（HTTP \(status)）")
        }
        return bytes
    }

    // MARK: - 长耗时请求（恢复备份 / 下载大文件 / 上传备份）

    /// 恢复备份是同步阻塞的：整库替换可能跑好几分钟，普通会话 90 秒就超时。
    /// 这里走 2 小时超时的会话，并且**不做 401 自动续期重试**——
    /// 恢复是一次性副作用操作，重放同一个请求等于再恢复一遍。
    func sendLongRunning(path: String,
                         method: String = "POST",
                         query: [String: String] = [:],
                         json: Any? = nil) async throws -> Data {
        let request = try makeRequest(path: path, method: method, query: query, json: json, authorized: true)
        return try await executeLong(request)
    }

    /// 下载二进制（备份文件）。返回内容与 Content-Disposition 里的文件名。
    func downloadBinary(path: String, query: [String: String] = [:]) async throws -> (data: Data, filename: String?) {
        let request = try makeRequest(path: path, method: "GET", query: query, json: nil, authorized: true)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await streamSession.data(for: request)
        } catch {
            throw PanelError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PanelError.transport("服务器没有返回有效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw errorFrom(data: data, status: http.statusCode)
        }
        return (data, Self.filename(from: http))
    }

    /// multipart 上传（备份文件）。文件名带中文时同时给 filename*，避免被截成乱码。
    func uploadMultipart(path: String,
                         field: String,
                         filename: String,
                         mimeType: String,
                         fileData: Data) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(Self.asciiFallbackName(filename))\"; filename*=UTF-8''\(Self.percentEncodedName(filename))\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = try makeRequest(path: path, method: "POST", query: [:], json: nil, authorized: true)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await executeLong(request)
    }

    private func executeLong(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await streamSession.data(for: request)
        } catch {
            throw PanelError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PanelError.transport("服务器没有返回有效响应")
        }
        if (200..<300).contains(http.statusCode) { return data }
        throw errorFrom(data: data, status: http.statusCode)
    }

    private func errorFrom(data: Data, status: Int) -> PanelError {
        let body = try? Self.decoder.decode(APIErrorBody.self, from: data)
        if status == 401 {
            return PanelError.unauthorized(message: body?.error, code: body?.code)
        }
        return PanelError.server(status: status,
                                 message: body?.error ?? "请求失败（HTTP \(status)）",
                                 code: body?.code)
    }

    private static func filename(from response: HTTPURLResponse) -> String? {
        guard let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
        // 形如 `attachment; filename="apitest.tgz"`，也可能带 filename*=UTF-8''...
        // filename* 优先（带中文名的备份只能靠它），普通的留作兜底。
        var plain: String?
        for part in disposition.split(separator: ";") {
            let text = part.trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix("filename*=") {
                let raw = String(text.dropFirst("filename*=".count))
                if let range = raw.range(of: "''"),
                   let decoded = String(raw[range.upperBound...]).removingPercentEncoding {
                    return decoded
                }
            }
            if text.lowercased().hasPrefix("filename=") {
                let raw = String(text.dropFirst("filename=".count))
                plain = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return plain
    }

    /// 面板只认扩展名，ASCII 兜底名也要保住后缀（`.tar.gz` 是双后缀）。
    private static func asciiFallbackName(_ name: String) -> String {
        if name.unicodeScalars.allSatisfy({ $0.isASCII }) { return name }
        let lowered = name.lowercased()
        let suffix: String
        if lowered.hasSuffix(".tar.gz") {
            suffix = ".tar.gz"
        } else if let dot = name.lastIndex(of: ".") {
            suffix = String(name[dot...])
        } else {
            suffix = ".tgz"
        }
        return "backup" + suffix
    }

    private static func percentEncodedName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}
