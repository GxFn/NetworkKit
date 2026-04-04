// MARK: - SSL Pinning

import Alamofire
import Foundation

/// SSL 证书/公钥 Pinning 配置
///
/// 创建 `PinnedSession` 可获得启用了 SSL Pinning 的 Alamofire Session。
/// 支持 证书 Pinning 和 公钥 Pinning 两种模式。
///
/// ```swift
/// // 公钥 Pinning（推荐：证书更新时不需要跟着改）
/// let session = PinnedSession.make(pins: [
///     .publicKeys(host: "api.example.com", validateChain: true)
/// ])
///
/// // 证书 Pinning
/// let session = PinnedSession.make(pins: [
///     .certificates(host: "api.example.com", validateChain: true)
/// ])
///
/// // 注入到 SessionPool 或 NetworkClient
/// let pool = SessionPool(apiConfig: .api)
/// ```
public enum PinnedSession {

    /// Pinning 策略
    public enum PinMode: Sendable {
        /// 公钥 Pinning：只验证证书中的公钥
        case publicKeys(host: String, validateChain: Bool = true)
        /// 证书 Pinning：验证完整证书
        case certificates(host: String, validateChain: Bool = true)
    }

    /// 创建带 SSL Pinning 的 Session
    ///
    /// - Parameters:
    ///   - pins: Pinning 配置列表
    ///   - configuration: URLSession 配置
    /// - Returns: 配置好的 Alamofire Session
    public static func make(
        pins: [PinMode],
        configuration: URLSessionConfiguration = .default
    ) -> Session {
        var evaluators: [String: ServerTrustEvaluating] = [:]

        for pin in pins {
            switch pin {
            case .publicKeys(let host, let validateChain):
                evaluators[host] = PublicKeysTrustEvaluator(
                    performDefaultValidation: validateChain
                )
            case .certificates(let host, let validateChain):
                evaluators[host] = PinnedCertificatesTrustEvaluator(
                    performDefaultValidation: validateChain
                )
            }
        }

        let manager = ServerTrustManager(evaluators: evaluators)
        return Session(configuration: configuration, serverTrustManager: manager)
    }
}
