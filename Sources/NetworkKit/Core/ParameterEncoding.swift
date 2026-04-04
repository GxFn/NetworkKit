// MARK: - Parameter Encoding

import Foundation

/// 请求参数编码方式
public enum ParameterEncoding: Sendable {

    /// URL query 编码（GET 请求默认）
    case url

    /// JSON body 编码（POST/PUT 等）
    case json

    /// Form body 编码（application/x-www-form-urlencoded）
    case form
}
