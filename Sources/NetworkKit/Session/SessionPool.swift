// MARK: - Session Pool

import Alamofire
import Foundation

/// 会话池：管理多个独立的 Alamofire Session
///
/// 每个 Session 拥有独立的 URLSessionConfiguration → 独立的 TCP 连接池。
/// 根据 `RequestPriority` 分发到不同 Session。
public final class SessionPool: Sendable {

    public static let shared = SessionPool()

    private let apiSession: Session
    private let liveSession: Session
    private let prefetchSession: Session

    public init(
        apiConfig: SessionConfig = .api,
        liveConfig: SessionConfig = .live,
        prefetchConfig: SessionConfig = .prefetch
    ) {
        self.apiSession = Self.makeSession(config: apiConfig)
        self.liveSession = Self.makeSession(config: liveConfig)
        self.prefetchSession = Self.makeSession(config: prefetchConfig)
    }

    /// 根据优先级获取对应的 Session
    public func session(for priority: RequestPriority) -> Session {
        switch priority {
        case .standard: return apiSession
        case .realtime: return liveSession
        case .prefetch: return prefetchSession
        }
    }

    private static func makeSession(config: SessionConfig) -> Session {
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = config.requestTimeout
        urlConfig.timeoutIntervalForResource = config.resourceTimeout
        urlConfig.httpMaximumConnectionsPerHost = config.maxConnections
        urlConfig.networkServiceType = config.serviceType
        urlConfig.waitsForConnectivity = config.waitsForConnectivity

        return Session(configuration: urlConfig)
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
