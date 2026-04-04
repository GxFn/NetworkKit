// MARK: - Network Error

import Alamofire
import Foundation

/// 网络层统一错误类型
///
/// 设计要点：
/// - 每个 case 携带 `requestID` 用于日志关联
/// - `isTransient` 属性区分可重试/不可重试
/// - `serverCode` 属性供认证中间件判断
public enum NetworkError: Error, Sendable {

    /// 无效 URL
    case invalidURL(String)

    /// 服务端业务错误 (HTTP 200 但业务 code 非成功值)
    case serverBusiness(code: Int, message: String, requestID: String)

    /// HTTP 状态码错误 (4xx/5xx)
    case httpStatus(code: Int, data: Data?, requestID: String)

    /// 传输层错误 (超时、连接丢失、DNS 解析失败)
    case transport(underlying: any Error, requestID: String)

    /// 响应解码失败
    case decoding(underlying: any Error, rawData: Data?, requestID: String)

    // MARK: - Retryability

    /// 是否为瞬态错误（可重试）
    public var isTransient: Bool {
        switch self {
        case .httpStatus(let code, _, _):
            return (500...599).contains(code) || code == 429
        case .transport:
            return true
        case .serverBusiness, .invalidURL, .decoding:
            return false
        }
    }

    /// 服务端业务错误码
    public var serverCode: Int? {
        if case .serverBusiness(let code, _, _) = self {
            return code
        }
        return nil
    }

    // MARK: - AFError Bridging

    /// 从 Alamofire 响应结果智能构造 NetworkError
    ///
    /// 利用 AFError 的 rich subcases 精准分类错误来源，
    /// 不再粗暴地将所有 AFError 归为 `.transport`。
    static func from(
        afError: AFError,
        response: HTTPURLResponse?,
        data: Data?,
        requestID: String
    ) -> NetworkError {
        switch afError {
        case .responseValidationFailed:
            // Alamofire .validate() 触发的状态码校验失败
            if let code = response?.statusCode {
                return .httpStatus(code: code, data: data, requestID: requestID)
            }
            return .transport(underlying: afError, requestID: requestID)

        case .responseSerializationFailed(let reason):
            // 响应序列化失败 → 归为解码错误
            if case .decodingFailed(let decodingError) = reason {
                return .decoding(underlying: decodingError, rawData: data, requestID: requestID)
            }
            return .decoding(underlying: afError, rawData: data, requestID: requestID)

        case .sessionTaskFailed(let underlying):
            // URLSession 层错误 → 保留原始 URLError
            return .transport(underlying: underlying, requestID: requestID)

        case .createURLRequestFailed(let underlying):
            // URLRequest 构建失败
            return .invalidURL(underlying.localizedDescription)

        case .requestAdaptationFailed, .requestRetryFailed:
            // Interceptor 层错误
            return .transport(underlying: afError, requestID: requestID)

        default:
            return .transport(underlying: afError, requestID: requestID)
        }
    }
}

// MARK: - LocalizedError

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .serverBusiness(let code, let message, let id):
            return "[\(id.prefix(8))] Server error(\(code)): \(message)"
        case .httpStatus(let code, _, let id):
            return "[\(id.prefix(8))] HTTP error: \(code)"
        case .transport(let underlying, let id):
            return "[\(id.prefix(8))] Transport error: \(underlying.localizedDescription)"
        case .decoding(let underlying, _, let id):
            return "[\(id.prefix(8))] Decoding error: \(underlying.localizedDescription)"
        }
    }
}
