// MARK: - Response Decoder

import Foundation

/// 响应校验协议
///
/// 让任何包含 code/message 的响应类型都能参与自动校验。
/// 业务方在自己的模块中让 Response 类型遵循此协议。
public protocol ResponseValidatable {
    var responseCode: Int { get }
    var responseMessage: String { get }
    var isSuccess: Bool { get }
}

/// 通用 JSON 响应解码器
///
/// 如果 Response 遵循 `ResponseValidatable`，自动校验业务状态码。
public struct ResponseDecoder: Sendable {

    private let jsonDecoder: JSONDecoder

    public static let `default` = ResponseDecoder(jsonDecoder: {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }())

    public init(jsonDecoder: JSONDecoder) {
        self.jsonDecoder = jsonDecoder
    }

    /// 解码响应数据
    ///
    /// 如果 Response 遵循 `ResponseValidatable`，自动校验 isSuccess。
    /// 如果校验失败，抛出 `NetworkError.serverBusiness`。
    public func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: RequestContext
    ) throws -> T {
        do {
            let result = try jsonDecoder.decode(T.self, from: data)

            if let validatable = result as? any ResponseValidatable {
                guard validatable.isSuccess else {
                    throw NetworkError.serverBusiness(
                        code: validatable.responseCode,
                        message: validatable.responseMessage,
                        requestID: context.id
                    )
                }
            }

            return result
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.decoding(underlying: error, rawData: data, requestID: context.id)
        }
    }
}
