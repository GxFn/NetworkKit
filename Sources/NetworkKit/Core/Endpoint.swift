// MARK: - Endpoint

import Foundation

/// 类型安全的请求端点描述
///
/// 泛型参数 `Response` 在编译期绑定返回类型，调用方无需传 `type:` 参数。
/// 所有 API 端点以静态工厂方法定义在 `Endpoint` 的 `where` 约束扩展中。
///
/// ```swift
/// let data = try await client.send(.popular(page: 1))
/// ```
public struct Endpoint<Response: Decodable & Sendable>: Sendable {

    public let path: String
    public let baseURL: String?
    public let method: HTTPMethod
    public let parameters: [String: any Sendable]?
    public let parameterEncoding: ParameterEncoding
    public let priority: RequestPriority
    public let requiresSigning: Bool
    public let timeout: TimeInterval?
    public let cachePolicy: CachePolicy

    public init(
        path: String,
        baseURL: String? = nil,
        method: HTTPMethod = .get,
        parameters: [String: any Sendable]? = nil,
        parameterEncoding: ParameterEncoding = .url,
        priority: RequestPriority = .standard,
        requiresSigning: Bool = false,
        timeout: TimeInterval? = nil,
        cachePolicy: CachePolicy = .none
    ) {
        self.path = path
        self.baseURL = baseURL
        self.method = method
        self.parameters = parameters
        self.parameterEncoding = parameterEncoding
        self.priority = priority
        self.requiresSigning = requiresSigning
        self.timeout = timeout
        self.cachePolicy = cachePolicy
    }
}
