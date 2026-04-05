// MARK: - Network Event Monitor

import Alamofire
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Network")

/// 基于 Alamofire EventMonitor 的请求生命周期监控
///
/// 替代手动日志中间件，利用 Alamofire 提供的完整生命周期回调：
/// - 请求开始/完成的结构化日志
/// - 自动采集 URLSessionTaskMetrics（DNS/TLS/连接/传输各阶段耗时）
/// - 向 MetricsCollector 上报聚合指标
public final class NetworkEventMonitor: EventMonitor {

    public let queue = DispatchQueue(label: "com.networkkit.event-monitor", qos: .utility)

    private let metricsCollector: MetricsCollector?

    public init(metricsCollector: MetricsCollector? = nil) {
        self.metricsCollector = metricsCollector
    }

    // MARK: - Request Lifecycle

    public func requestDidResume(_ request: Request) {
        let method = request.request?.httpMethod ?? "?"
        let url = request.request?.url?.path ?? "unknown"
        logger.debug("→ \(method) \(url)")
    }

    public func request(_ request: Request, didValidateRequest urlRequest: URLRequest?, response: HTTPURLResponse, data: Data?, withResult result: Request.ValidationResult) {
        switch result {
        case .success:
            break
        case .failure(let error):
            let path = urlRequest?.url?.path ?? "unknown"
            logger.warning("✖ Validation failed: \(path) — \(error.localizedDescription)")
        }
    }

    // MARK: - Task Metrics (DNS/TLS/Transfer timing)

    public func request(_ request: Request, didGatherMetrics metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last,
              let urlRequest = request.request else {
            return
        }

        let path = urlRequest.url?.path ?? "unknown"
        let method = urlRequest.httpMethod ?? "GET"
        let statusCode = (transaction.response as? HTTPURLResponse)?.statusCode

        // 从 URLSessionTaskMetrics 提取精确耗时
        let duration: TimeInterval
        if let start = transaction.fetchStartDate, let end = transaction.responseEndDate {
            duration = end.timeIntervalSince(start)
        } else {
            duration = metrics.taskInterval.duration
        }

        let bytesSent = transaction.countOfRequestBodyBytesSent
        let bytesReceived = transaction.countOfResponseBodyBytesReceived

        // 上报到 MetricsCollector
        metricsCollector?.record(RequestMetrics(
            path: path,
            method: method,
            statusCode: statusCode,
            duration: duration,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived,
            succeeded: statusCode.map { (200..<300).contains($0) } ?? false,
            errorType: nil
        ))

        // 结构化日志（仅 debug 级别，Release 自动丢弃）
        if let dns = transaction.domainLookupStartDate,
           let dnsEnd = transaction.domainLookupEndDate,
           let connectStart = transaction.connectStartDate,
           let secureStart = transaction.secureConnectionStartDate,
           let secureEnd = transaction.secureConnectionEndDate {
            let dnsMs = dnsEnd.timeIntervalSince(dns) * 1000
            let tlsMs = secureEnd.timeIntervalSince(secureStart) * 1000
            let connectMs = secureEnd.timeIntervalSince(connectStart) * 1000
            logger.debug("⏱ \(path) DNS=\(String(format: "%.0f", dnsMs))ms TLS=\(String(format: "%.0f", tlsMs))ms Conn=\(String(format: "%.0f", connectMs))ms Total=\(String(format: "%.0f", duration * 1000))ms")
        }
    }

    // MARK: - Error Tracking

    public func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        guard let error = response.error else { return }

        let path = request.request?.url?.path ?? "unknown"
        let method = request.request?.httpMethod ?? "GET"
        let duration = response.metrics.map { $0.taskInterval.duration } ?? 0

        metricsCollector?.record(RequestMetrics(
            path: path,
            method: method,
            statusCode: response.response?.statusCode,
            duration: duration,
            succeeded: false,
            errorType: String(describing: type(of: error))
        ))

        logger.warning("✖ \(method) \(path) — \(error.localizedDescription)")
    }
}
