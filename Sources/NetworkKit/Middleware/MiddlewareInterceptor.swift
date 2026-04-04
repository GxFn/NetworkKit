// MARK: - Middleware Interceptor Bridge

import Alamofire
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Interceptor")

// MARK: - Middleware → Alamofire Adapter

/// 将单个 NetworkKit Middleware 的 `adapt` 包装为 Alamofire `RequestAdapter`
///
/// **仅适用于无状态、不依赖 RequestContext 的中间件**（如 `DefaultHeadersMiddleware`）。
///
/// > ⚠️ 需要 `RequestContext` 的中间件（如 `SigningMiddleware`、`RateLimitMiddleware`）
/// > 应放在 `NetworkClient(middlewares:)` 的 Pipeline 级别，由 NetworkClient 在 `execute()`
/// > 中以完整的 `RequestContext` 调用 `adapt()`。
/// > 此处创建的是临时 Context（无 `requiresSigning`/`priority` 等元数据），
/// > 会导致依赖 Context 的中间件行为不正确。
public struct MiddlewareAdapter: RequestAdapter {

    private let middleware: any Middleware

    public init(_ middleware: any Middleware) {
        self.middleware = middleware
    }

    public func adapt(
        _ urlRequest: URLRequest,
        for session: Alamofire.Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        Task {
            do {
                let context = RequestContext(
                    id: UUID().uuidString,
                    path: urlRequest.url?.path ?? ""
                )
                let adapted = try await middleware.adapt(urlRequest, context: context)
                completion(.success(adapted))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Factory

/// 从 Alamofire 原生组件构建 `Interceptor`
///
/// ## 设计原则
///
/// - **Session 级别**（此函数）：处理无状态的请求修改 + 传输层重试
/// - **Pipeline 级别**（NetworkClient.middlewares）：处理有状态的 adapt/didReceive/recover
///
/// Middleware 的 `recover()` **不在此处桥接**为 Alamofire Retrier。
/// 业务级恢复（token 刷新、限流重试等）统一在 NetworkClient 的 `attemptBusinessRecovery` 中执行，
/// 避免与 `NetworkKitRetryPolicy` 产生双重重试。
///
/// ```swift
/// // Session 级别：无状态 adapter + 传输层重试
/// let interceptor = makeInterceptor(
///     adapters: [
///         MiddlewareAdapter(DefaultHeadersMiddleware(headers: ["User-Agent": "BiliDili/1.0"])),
///     ],
///     retryPolicy: NetworkKitRetryPolicy(retryLimit: 3)
/// )
/// let pool = SessionPool(interceptor: interceptor)
///
/// // Pipeline 级别：有状态中间件（需要 RequestContext）
/// let client = NetworkClient(
///     defaultBaseURL: "https://api.bilibili.com",
///     sessionPool: pool,
///     middlewares: [SigningMiddleware(signer: wbi), RateLimitMiddleware(...), CacheMiddleware()]
/// )
/// ```
public func makeInterceptor(
    adapters: [any RequestAdapter] = [],
    retryPolicy: RetryPolicy? = nil,
    additionalRetriers: [any RequestRetrier] = []
) -> Interceptor {
    var retriers = [any RequestRetrier]()

    // Alamofire RetryPolicy 处理传输层重试（超时/DNS/连接中断等）
    if let retryPolicy {
        retriers.append(retryPolicy)
    }

    // 额外的自定义 Retrier（如 OAuth token 刷新）
    retriers.append(contentsOf: additionalRetriers)

    return Interceptor(adapters: adapters, retriers: retriers)
}
