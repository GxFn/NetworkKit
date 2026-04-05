// MARK: - Signing Middleware

import Foundation

/// 通用请求签名中间件
///
/// 当 `Endpoint.requiresSigning == true` 时，使用注入的 `RequestSigner` 对请求签名。
/// 网络模块不知道具体签名算法（WBI / HMAC / OAuth），只调用 `signer.sign()`。
public struct SigningMiddleware: Middleware {

    private let signer: any RequestSigner

    public init(signer: any RequestSigner) {
        self.signer = signer
    }

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        guard context.requiresSigning else { return request }

        guard let originalURL = request.url,
              let components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else {
            return request
        }

        // 提取现有 query 参数
        var params: [String: any Sendable] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value {
                params[item.name] = value
            }
        }

        let signedURL = try await signer.sign(url: originalURL, parameters: params)

        var mutableRequest = request
        mutableRequest.url = signedURL
        return mutableRequest
    }
}
