// MARK: - Network Reachability

import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.networkkit", category: "Reachability")

/// 网络连接状态
public enum ReachabilityStatus: Sendable, Equatable {
    case unknown
    case unreachable
    case wifi
    case cellular
    case wiredEthernet
}

/// 网络可达性监控器
///
/// 基于 `NWPathMonitor`，支持 `AsyncSequence` 监听状态变化。
///
/// ```swift
/// let reachability = NetworkReachability.shared
/// reachability.start()
///
/// // 当前状态
/// let status = reachability.currentStatus
///
/// // 监听变化
/// for await status in reachability.statusStream {
///     print("Network: \(status)")
/// }
/// ```
public final class NetworkReachability: Sendable {

    public static let shared = NetworkReachability()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.networkkit.reachability")

    /// 单一状态锁：保护 status + continuations，避免双锁间竞态
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State: Sendable {
        var status: ReachabilityStatus = .unknown
        var continuations: [UUID: AsyncStream<ReachabilityStatus>.Continuation] = [:]
    }

    /// 当前网络状态
    public var currentStatus: ReachabilityStatus {
        state.withLock { $0.status }
    }

    /// 是否可达
    public var isReachable: Bool {
        let status = currentStatus
        return status != .unreachable && status != .unknown
    }

    public init() {
        self.monitor = NWPathMonitor()
    }

    /// 开始监控
    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let newStatus = Self.mapStatus(path)

            // 单锁内同时更新状态 + 通知观察者，保证一致性
            let shouldNotify = self.state.withLock { s -> Bool in
                guard s.status != newStatus else { return false }
                let old = s.status
                s.status = newStatus
                for (_, continuation) in s.continuations {
                    continuation.yield(newStatus)
                }
                logger.info("Network status: \(String(describing: old)) → \(String(describing: newStatus))")
                return true
            }
            _ = shouldNotify
        }
        monitor.start(queue: queue)
    }

    /// 停止监控
    public func stop() {
        monitor.cancel()
        state.withLock { s in
            for (_, continuation) in s.continuations {
                continuation.finish()
            }
            s.continuations.removeAll()
        }
    }

    /// 状态变化的 AsyncStream
    public var statusStream: AsyncStream<ReachabilityStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
            self.state.withLock { s in
                s.continuations[id] = continuation
                // 立即发送当前状态
                continuation.yield(s.status)
            }
        }
    }

    // MARK: - Private

    private static func mapStatus(_ path: NWPath) -> ReachabilityStatus {
        guard path.status == .satisfied else { return .unreachable }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return .wifi  // loopback 等也视为可用
        }
    }
}
