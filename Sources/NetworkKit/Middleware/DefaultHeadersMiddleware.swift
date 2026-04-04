// MARK: - Default Headers Middleware

import Foundation

/// 默认请求头注入中间件
///
/// 集中管理 User-Agent、Accept、Accept-Language 等公共请求头。
///
/// ```swift
/// let headers = DefaultHeadersMiddleware(headers: [
///     "User-Agent": "MyApp/1.0",
///     "Accept": "application/json",
///     "Accept-Language": "zh-CN"
/// ])
/// ```
public struct DefaultHeadersMiddleware: Middleware {

    private let headers: [String: String]

    /// - Parameter headers: 要注入的默认请求头（不会覆盖已有的同名 Header）
    public init(headers: [String: String]) {
        self.headers = headers
    }

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        var request = request
        for (key, value) in headers {
            if request.value(forHTTPHeaderField: key) == nil {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        return request
    }

    public func recover(from error: NetworkError, context: RequestContext) async throws -> RecoveryAction? {
        nil
    }
}
