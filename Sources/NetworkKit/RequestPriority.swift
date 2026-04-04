// MARK: - Request Priority

import Foundation

/// 请求优先级，决定走哪个 Alamofire Session
///
/// 每个优先级对应一个独立的 URLSession（独立连接池 + 独立 TCP 连接）
public enum RequestPriority: Sendable {

    /// 用户触发的常规 API（Feed、详情、关注、搜索）
    case standard

    /// 延迟敏感请求（playURL、实时数据等）
    case realtime

    /// 后台预取（预加载推荐等）
    case prefetch
}
