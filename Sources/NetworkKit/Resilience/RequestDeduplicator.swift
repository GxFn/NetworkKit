// MARK: - Request Deduplicator

import Foundation
import os

private let logger = Logger(subsystem: "com.networkkit", category: "Dedup")

/// 请求去重器
///
/// 对相同 key 的并发请求只发一次网络请求，其他等待者共享结果。
/// 适用于短时间内重复触发的 API 请求（如快速切 Tab 重复加载 Feed）。
///
/// ```swift
/// let dedup = RequestDeduplicator()
///
/// // 3 次并发调用只发 1 次网络请求
/// async let a = dedup.deduplicate(key: "popular-1") { try await client.send(.popular(page: 1)) }
/// async let b = dedup.deduplicate(key: "popular-1") { try await client.send(.popular(page: 1)) }
/// async let c = dedup.deduplicate(key: "popular-1") { try await client.send(.popular(page: 1)) }
/// ```
public final class RequestDeduplicator: Sendable {

    private let inFlight = OSAllocatedUnfairLock(
        initialState: [String: Task<any Sendable, any Error>]()
    )

    public init() {}

    /// 去重执行
    ///
    /// - Parameters:
    ///   - key: 请求唯一标识（通常是 path + 关键参数的组合）
    ///   - work: 实际网络请求闭包
    /// - Returns: 请求结果
    public func deduplicate<T: Sendable>(
        key: String,
        work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        // 先检查后注册必须在同一个 lock 区间内，防止 TOCTOU 竞态
        let (task, isNew) = inFlight.withLock { flights -> (Task<any Sendable, any Error>, Bool) in
            if let existing = flights[key] {
                return (existing, false)
            }
            let newTask: Task<any Sendable, any Error> = Task { try await work() }
            flights[key] = newTask
            return (newTask, true)
        }

        if !isNew {
            logger.debug("Dedup hit: \(key)")
        }

        do {
            let value = try await task.value
            if isNew {
                inFlight.withLock { _ = $0.removeValue(forKey: key) }
            }
            guard let typed = value as? T else {
                throw NetworkError.decoding(
                    underlying: DeduplicatorTypeMismatch(expected: "\(T.self)", actual: "\(type(of: value))"),
                    rawData: nil,
                    requestID: UUID().uuidString
                )
            }
            return typed
        } catch {
            if isNew {
                inFlight.withLock { _ = $0.removeValue(forKey: key) }
            }
            throw error
        }
    }
}

private struct DeduplicatorTypeMismatch: Error, LocalizedError {
    let expected: String
    let actual: String
    var errorDescription: String? {
        "Dedup type mismatch: expected \(expected), got \(actual)"
    }
}
