import Foundation

/// 面板出错时的响应体：`{"error": "...", "code": "..."}`（code 只在部分接口出现）。
struct APIErrorBody: Decodable {
    let error: String?
    let code: String?
}

/// 单对象接口的常见包装：`{"data": {...}}`。
/// 客户端解码时先按包装解，解不出来再按裸对象解，兼容两种返回口径。
struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

/// 分页接口的包装：`{"data": [...], "total": n, "page": 1, "page_size": 20}`。
struct PagedEnvelope<T: Decodable>: Decodable {
    let data: [T]?
    let total: Int?
    let page: Int?
    let pageSize: Int?
}

struct PagedResult<T> {
    var items: [T]
    var total: Int
    var page: Int
    var pageSize: Int

    var hasMore: Bool { items.count < total }

    static var empty: PagedResult<T> {
        PagedResult(items: [], total: 0, page: 1, pageSize: 0)
    }
}

struct EmptyResponse: Decodable {}
