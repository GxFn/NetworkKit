// MARK: - Network Client

import Alamofire
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Network")

/// 网络客户端协议
///
/// 面向协议设计，Repository 持有 `any NetworkClientProtocol`。
/// 测试时可注入 Mock 实现。
public protocol NetworkClientProtocol: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint<T>) async throws -> T
}

/// 网络客户端：请求发送 + 中间件编排
///
/// 整个网络层的 **唯一出口**。
/// 调用流程：
/// ```
/// Endpoint → RequestContext → adapt(URLRequest) → Session.request → decode → return
///                     ↑ retry ← recover(error) ← catch
/// ```
public struct NetworkClient: NetworkClientProtocol {

    /// 默认 baseURL（Endpoint 未指定 baseURL 时使用）
    public let defaultBaseURL: String

    private let sessionPool: SessionPool
    private let middlewares: [any Middleware]
    private let decoder: ResponseDecoder

    public init(
        defaultBaseURL: String,
        sessionPool: SessionPool = .shared,
        middlewares: [any Middleware] = [],
        decoder: ResponseDecoder = .default
    ) {
        self.defaultBaseURL = defaultBaseURL
        self.sessionPool = sessionPool
        self.middlewares = middlewares
        self.decoder = decoder
    }

    // MARK: - Send

    public func send<T: Decodable & Sendable>(_ endpoint: Endpoint<T>) async throws -> T {
        let context = RequestContext(endpoint: endpoint)
        return try await execute(endpoint, context: context)
    }

    // MARK: - Core Pipeline

    private func execute<T: Decodable & Sendable>(
        _ endpoint: Endpoint<T>,
        context: RequestContext
    ) async throws -> T {
        do {
            // 1. 构建 URLRequest
            var urlRequest = try buildURLRequest(endpoint)

            // 2. 中间件 adapt 链
            for middleware in middlewares {
                urlRequest = try await middleware.adapt(urlRequest, context: context)
            }

            // 3. 选择 Session 并发送
            let session = sessionPool.session(for: endpoint.priority)
            let data = try await performRequest(urlRequest, session: session, context: context)

            // 4. 解码
            let result = try decoder.decode(T.self, from: data, context: context)

            logger.debug("[\(context.id.prefix(8))] ✔ \(endpoint.path) (\(String(format: "%.0f", context.elapsed * 1000))ms)")
            return result

        } catch let error as NetworkError {
            return try await attemptRecovery(from: error, endpoint: endpoint, context: context)
        } catch {
            let networkError = NetworkError.transport(underlying: error, requestID: context.id)
            return try await attemptRecovery(from: networkError, endpoint: endpoint, context: context)
        }
    }

    // MARK: - Recovery

    private func attemptRecovery<T: Decodable & Sendable>(
        from error: NetworkError,
        endpoint: Endpoint<T>,
        context: RequestContext
    ) async throws -> T {
        for middleware in middlewares {
            if let action = try await middleware.recover(from: error, context: context) {
                switch action {
                case .retry(let delay):
                    context.incrementRetry()
                    try await Task.sleep(for: .seconds(delay))
                    return try await execute(endpoint, context: context)
                }
            }
        }
        throw error
    }

    // MARK: - Build URLRequest

    private func buildURLRequest<T>(_ endpoint: Endpoint<T>) throws -> URLRequest {
        let baseURL = endpoint.baseURL ?? defaultBaseURL
        let urlString = baseURL + endpoint.path

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

        if let timeout = endpoint.timeout {
            request.timeoutInterval = timeout
        }

        // 编码参数
        if let parameters = endpoint.parameters {
            try encodeParameters(parameters, into: &request, encoding: endpoint.parameterEncoding)
        }

        return request
    }

    // MARK: - Parameter Encoding

    private func encodeParameters(
        _ parameters: [String: any Sendable],
        into request: inout URLRequest,
        encoding: ParameterEncoding
    ) throws {
        let stringParams = parameters.mapValues { "\($0)" }

        switch encoding {
        case .url:
            guard var components = URLComponents(
                url: request.url!,
                resolvingAgainstBaseURL: false
            ) else {
                throw NetworkError.invalidURL(request.url?.absoluteString ?? "")
            }
            let newItems = stringParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            var items = components.queryItems ?? []
            items.append(contentsOf: newItems)
            components.queryItems = items
            request.url = components.url

        case .json:
            request.httpBody = try JSONSerialization.data(withJSONObject: stringParams)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
    }

    // MARK: - Perform Request

    private func performRequest(
        _ request: URLRequest,
        session: Session,
        context: RequestContext
    ) async throws -> Data {
        let response = await session.request(request).serializingData().response

        if let httpResponse = response.response {
            let statusCode = httpResponse.statusCode
            if !(200..<300).contains(statusCode) {
                throw NetworkError.httpStatus(
                    code: statusCode,
                    data: response.data,
                    requestID: context.id
                )
            }
        }

        guard let data = response.data else {
            throw NetworkError.transport(
                underlying: response.error ?? URLError(.badServerResponse),
                requestID: context.id
            )
        }

        if let afError = response.error, data.isEmpty {
            throw NetworkError.transport(underlying: afError, requestID: context.id)
        }

        return data
    }
}
