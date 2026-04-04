// MARK: - Retry Middleware

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Retry")

/// 瞬态错误重试中间件（指数退避）
public struct RetryMiddleware: Middleware {

    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval

    public init(maxRetries: Int = 3, baseDelay: TimeInterval = 0.3, maxDelay: TimeInterval = 5) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        request
    }

    public func recover(from error: NetworkError, context: RequestContext) async throws -> RecoveryAction? {
        guard error.isTransient, context.retryCount < maxRetries else {
            return nil
        }

        let delay = min(baseDelay * pow(2, Double(context.retryCount)), maxDelay)
        logger.info("[\(context.id.prefix(8))] Retry #\(context.retryCount + 1) after \(String(format: "%.1f", delay))s — \(context.path)")
        return .retry(after: delay)
    }
}
