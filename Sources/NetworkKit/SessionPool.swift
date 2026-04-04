// MARK: - Session Pool

import Alamofire
import Foundation
import os

/// 会话池：管理多个独立的 Alamofire Session
///
/// 每个 Session 拥有独立的 URLSessionConfiguration → 独立的 TCP 连接池。
/// 根据 `RequestPriority` 分发到不同 Session。
public final class SessionPool: Sendable {

    public static let shared = SessionPool()

    private let apiSession: Session
    private let liveSession: Session
    private let prefetchSession: Session

    let activityMonitor = ActivityMonitor()

    public init(
        apiConfig: SessionConfig = .api,
        liveConfig: SessionConfig = .live,
        prefetchConfig: SessionConfig = .prefetch
    ) {
        let monitors: [any EventMonitor] = [activityMonitor]
        self.apiSession = Self.makeSession(config: apiConfig, monitors: monitors)
        self.liveSession = Self.makeSession(config: liveConfig, monitors: monitors)
        self.prefetchSession = Self.makeSession(config: prefetchConfig, monitors: monitors)
    }

    func session(for priority: RequestPriority) -> Session {
        switch priority {
        case .standard: return apiSession
        case .realtime: return liveSession
        case .prefetch: return prefetchSession
        }
    }

    private static func makeSession(
        config: SessionConfig,
        monitors: [any EventMonitor]
    ) -> Session {
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = config.requestTimeout
        urlConfig.timeoutIntervalForResource = config.resourceTimeout
        urlConfig.httpMaximumConnectionsPerHost = config.maxConnections
        urlConfig.networkServiceType = config.serviceType
        urlConfig.waitsForConnectivity = config.waitsForConnectivity

        return Session(configuration: urlConfig, eventMonitors: monitors)
    }
}

// MARK: - Session Configuration

/// Session 配置值对象
public struct SessionConfig: Sendable {
    public let requestTimeout: TimeInterval
    public let resourceTimeout: TimeInterval
    public let maxConnections: Int
    public let serviceType: URLRequest.NetworkServiceType
    public let waitsForConnectivity: Bool

    public init(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        maxConnections: Int,
        serviceType: URLRequest.NetworkServiceType,
        waitsForConnectivity: Bool
    ) {
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.maxConnections = maxConnections
        self.serviceType = serviceType
        self.waitsForConnectivity = waitsForConnectivity
    }

    /// 普通 API: Feed、详情、搜索
    public static let api = SessionConfig(
        requestTimeout: 30,
        resourceTimeout: 60,
        maxConnections: 6,
        serviceType: .default,
        waitsForConnectivity: false
    )

    /// 实时: 延迟敏感请求
    public static let live = SessionConfig(
        requestTimeout: 15,
        resourceTimeout: 30,
        maxConnections: 4,
        serviceType: .responsiveAV,
        waitsForConnectivity: false
    )

    /// 后台预取: 预加载
    public static let prefetch = SessionConfig(
        requestTimeout: 60,
        resourceTimeout: 120,
        maxConnections: 2,
        serviceType: .background,
        waitsForConnectivity: true
    )
}

// MARK: - Activity Monitor

/// 网络活跃请求监控器
final class ActivityMonitor: EventMonitor, @unchecked Sendable {

    let queue = DispatchQueue(label: "com.networkkit.activityMonitor")

    private let activeRequestIDs = OSAllocatedUnfairLock(initialState: Set<UUID>())

    /// 当前活跃请求数
    var activeCount: Int {
        activeRequestIDs.withLock { $0.count }
    }

    /// 是否有活跃请求
    var isActive: Bool {
        activeCount > 0
    }

    // MARK: - EventMonitor 回调

    func requestDidResume(_ request: Request) {
        activeRequestIDs.withLock { $0.insert(request.id) }
    }

    func requestDidSuspend(_ request: Request) {
        activeRequestIDs.withLock { $0.remove(request.id) }
    }

    func requestDidCancel(_ request: Request) {
        activeRequestIDs.withLock { $0.remove(request.id) }
    }

    func requestDidFinish(_ request: Request) {
        activeRequestIDs.withLock { $0.remove(request.id) }
    }
}
