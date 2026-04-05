// MARK: - Middleware Protocol

import Foundation

/// 请求中间件协议
///
/// 设计思想：每个关注点独立成一个 Middleware，可组合、可插拔。
/// - `adapt`: 请求发出前修改 URLRequest (注入 Header、Cookie、签名)
/// - `didReceive`: 收到响应后，可检查/转换响应数据
/// - `recover`: 请求失败后判断是否可恢复 (认证刷新、重试)
public protocol Middleware: Sendable {

    /// 请求发出前：注入 Header、签名、Cookie 等
    func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest

    /// 收到响应后：可检查、记录或转换响应数据
    /// 默认实现直接透传
    func didReceive(data: Data, response: URLResponse, context: RequestContext) async throws -> Data

    /// 请求失败后：判断是否可恢复
    /// - Returns: `nil` 表示不处理，交给链中下一个中间件
    func recover(from error: NetworkError, context: RequestContext) async throws -> RecoveryAction?
}

// MARK: - Default Implementation

extension Middleware {
    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        request
    }

    public func didReceive(data: Data, response: URLResponse, context: RequestContext) async throws -> Data {
        data
    }

    public func recover(from error: NetworkError, context: RequestContext) async throws -> RecoveryAction? {
        nil
    }
}

// MARK: - Recovery Action

/// 中间件恢复动作
public enum RecoveryAction: Sendable {
    /// 延迟后重试原请求
    case retry(after: TimeInterval)
}
