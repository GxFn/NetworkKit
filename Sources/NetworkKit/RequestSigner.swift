// MARK: - Request Signer Protocol

import Foundation

/// 请求签名协议
///
/// 网络层只定义签名的抽象接口，不关心具体签名算法（WBI、HMAC、OAuth 等）。
/// 业务方自行实现并注入到 `SigningMiddleware`。
public protocol RequestSigner: Sendable {
    /// 对请求 URL 和参数进行签名，返回签名后的完整 URL
    func sign(url: URL, parameters: [String: any Sendable]) async throws -> URL
}
