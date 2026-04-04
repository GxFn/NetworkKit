// MARK: - Request Context

import Foundation
import os

/// 请求上下文：贯穿整个请求生命周期
///
/// 携带唯一 ID + 元数据，用于日志链路追踪和中间件通信。
public final class RequestContext: @unchecked Sendable {

    /// 请求唯一标识 (UUID)
    public let id: String

    /// 请求创建时间
    public let startTime: Date

    /// 请求优先级
    public let priority: RequestPriority

    /// 是否需要请求签名
    public let requiresSigning: Bool

    /// 请求路径 (用于日志)
    public let path: String

    /// 当前重试次数 (线程安全)
    private let _retryCount = OSAllocatedUnfairLock(initialState: 0)

    public var retryCount: Int {
        _retryCount.withLock { $0 }
    }

    public func incrementRetry() {
        _retryCount.withLock { $0 += 1 }
    }

    public init<R>(endpoint: Endpoint<R>) {
        self.id = UUID().uuidString
        self.startTime = Date()
        self.priority = endpoint.priority
        self.requiresSigning = endpoint.requiresSigning
        self.path = endpoint.path
    }

    /// 请求耗时 (秒)
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}
