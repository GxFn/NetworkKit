// MARK: - Request Priority

import Foundation

/// 请求优先级，决定走哪个 Alamofire Session
///
/// 每个优先级对应一个独立的 URLSession（独立连接池 + 独立 TCP 连接）。
/// 仅用于 Alamofire 管理的请求路由。
/// 对于 delegate-based 场景（AVPlayer、WebSocket），使用
/// `SessionPool.makeDelegateSession(config:)` 并传入 `SessionConfig` 预设。
public enum RequestPriority: Sendable {

    /// 用户触发的常规 API（Feed、详情、关注、搜索）
    case standard

    /// 延迟敏感请求（playURL、实时数据等）
    case realtime

    /// 后台预取（预加载推荐等）
    case prefetch

    /// 上传（独立于 API 的上传通道）
    case upload

    /// 下载（长超时、低并发、独立连接池）
    case download
}
