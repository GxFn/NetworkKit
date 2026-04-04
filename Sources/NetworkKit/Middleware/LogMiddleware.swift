// MARK: - Log Middleware

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Network")

/// 日志中间件：结构化记录请求/响应摘要
///
/// 使用 os.Logger 输出，Release 下 debug 级别自动丢弃。
public struct LogMiddleware: Middleware {

    public init() {}

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        logger.debug("[\(context.id.prefix(8))] → \(request.httpMethod ?? "GET") \(request.url?.path ?? "unknown") P=\(String(describing: context.priority))")
        return request
    }

    public func recover(from error: NetworkError, context: RequestContext) async throws -> RecoveryAction? {
        logger.warning("[\(context.id.prefix(8))] ✖ \(error.localizedDescription) (\(String(format: "%.0f", context.elapsed * 1000))ms)")
        return nil
    }
}
