// MARK: - Endpoint

import Alamofire
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

// MARK: - URLRequest Builder

extension Endpoint {

    /// 构建 URLRequest，使用 Alamofire ParameterEncoder 统一编码参数
    ///
    /// - Parameter defaultBaseURL: 当 Endpoint 未指定 baseURL 时使用
    /// - Returns: 编码完成的 URLRequest
    public func asURLRequest(baseURL defaultBaseURL: String) throws -> URLRequest {
        let base = baseURL ?? defaultBaseURL
        let urlString = base + path

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        if let timeout {
            request.timeoutInterval = timeout
        }

        guard let parameters else { return request }

        switch parameterEncoding {
        case .url:
            // Alamofire URLEncodedFormParameterEncoder: 编码到 URL query
            let stringParams = parameters.mapValues { "\($0)" }
            request = try URLEncodedFormParameterEncoder.default.encode(
                stringParams, into: request
            )

        case .json:
            // JSONSerialization 保留原始类型（Bool/Int/Double/String/Array/Dict）
            let jsonObject = parameters.mapValues { Self.toJSONCompatible($0) }
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

        case .form:
            // Alamofire URLEncodedFormParameterEncoder: 编码到 HTTP body
            let stringParams = parameters.mapValues { "\($0)" }
            request = try URLEncodedFormParameterEncoder(
                destination: .httpBody
            ).encode(stringParams, into: request)
        }

        return request
    }

    /// 将 `any Sendable` 转为 JSON 兼容类型，保留原始类型信息
    private static func toJSONCompatible(_ value: any Sendable) -> Any {
        switch value {
        case let v as Bool: return v
        case let v as Int: return v
        case let v as Int64: return v
        case let v as Double: return v
        case let v as Float: return v
        case let v as String: return v
        case let v as [any Sendable]: return v.map { toJSONCompatible($0) }
        case let v as [String: any Sendable]: return v.mapValues { toJSONCompatible($0) }
        default: return "\(value)"
        }
    }
}
