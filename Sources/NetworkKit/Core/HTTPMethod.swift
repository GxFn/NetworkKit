// MARK: - HTTP Method

import Alamofire
import Foundation

/// HTTP 请求方法
///
/// NetworkKit 自有类型，不暴露 Alamofire 依赖给消费方。
public struct HTTPMethod: RawRepresentable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let get     = HTTPMethod(rawValue: "GET")
    public static let post    = HTTPMethod(rawValue: "POST")
    public static let put     = HTTPMethod(rawValue: "PUT")
    public static let delete  = HTTPMethod(rawValue: "DELETE")
    public static let patch   = HTTPMethod(rawValue: "PATCH")
    public static let head    = HTTPMethod(rawValue: "HEAD")
    public static let options = HTTPMethod(rawValue: "OPTIONS")

    /// 转为 Alamofire HTTPMethod（模块内部使用）
    var alamofire: Alamofire.HTTPMethod {
        Alamofire.HTTPMethod(rawValue: rawValue)
    }
}
