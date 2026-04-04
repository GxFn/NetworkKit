// MARK: - WebSocket Client

import Foundation
import os

private let logger = Logger(subsystem: "com.networkkit", category: "WebSocket")

/// WebSocket 消息类型
public enum WebSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

/// WebSocket 连接状态
public enum WebSocketState: Sendable, Equatable {
    case connecting
    case connected
    case disconnected(reason: String?)
}

/// WebSocket 客户端
///
/// 基于 `URLSessionWebSocketTask`，支持自动重连和 AsyncSequence 消息流。
/// 使用共享的 `messages` stream，所有观察者接收相同的消息。
///
/// ```swift
/// let ws = WebSocketClient(url: URL(string: "wss://live.example.com/room/123")!)
///
/// // 获取消息流（必须在 connect 之前）
/// let stream = ws.messages
///
/// try await ws.connect()
/// try await ws.send(.text("{\"action\":\"join\"}"))
///
/// for await message in stream {
///     switch message {
///     case .text(let json): handleJSON(json)
///     case .data(let bytes): handleBinary(bytes)
///     }
/// }
/// ```
public final actor WebSocketClient {

    private let url: URL
    private let headers: [String: String]
    private let autoReconnect: Bool
    private let maxReconnectAttempts: Int
    private let reconnectBaseDelay: TimeInterval
    private let sessionPool: SessionPool

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectCount = 0
    private var intentionalDisconnect = false
    private var receiveLoopTask: Task<Void, Never>?

    /// 消息广播：支持多个监听者
    private var continuations: [UUID: AsyncStream<WebSocketMessage>.Continuation] = [:]

    private(set) public var state: WebSocketState = .disconnected(reason: nil)

    public init(
        url: URL,
        headers: [String: String] = [:],
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 5,
        reconnectBaseDelay: TimeInterval = 1.0,
        sessionPool: SessionPool = .shared
    ) {
        self.url = url
        self.headers = headers
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBaseDelay = reconnectBaseDelay
        self.sessionPool = sessionPool
    }

    // MARK: - Connect / Disconnect

    /// 建立连接
    public func connect() async throws {
        intentionalDisconnect = false
        reconnectCount = 0

        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let session = sessionPool.makeDelegateSession(config: .websocket)
        let wsTask = session.webSocketTask(with: request)

        self.session = session
        self.task = wsTask
        self.state = .connecting

        wsTask.resume()

        // 用 ping 验证连接是否真的建立
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                wsTask.sendPing { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            }
            self.state = .connected
            logger.info("WebSocket connected: \(self.url.absoluteString)")
        } catch {
            cleanup(reason: "Connection failed: \(error.localizedDescription)")
            throw NetworkError.transport(underlying: error, requestID: UUID().uuidString)
        }

        startReceiveLoop()
    }

    /// 断开连接
    public func disconnect(reason: String? = nil) {
        intentionalDisconnect = true
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        task?.cancel(with: .normalClosure, reason: reason?.data(using: .utf8))
        cleanup(reason: reason ?? "intentional")
    }

    // MARK: - Send

    /// 发送消息
    public func send(_ message: WebSocketMessage) async throws {
        guard let task, state == .connected else {
            throw NetworkError.transport(
                underlying: URLError(.notConnectedToInternet),
                requestID: UUID().uuidString
            )
        }

        switch message {
        case .text(let string):
            try await task.send(.string(string))
        case .data(let data):
            try await task.send(.data(data))
        }
    }

    // MARK: - Message Stream

    /// 消息接收 AsyncStream（可多次调用，每个调用者获得独立的 stream）
    public nonisolated var messages: AsyncStream<WebSocketMessage> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addContinuation(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func addContinuation(_ continuation: AsyncStream<WebSocketMessage>.Continuation, id: UUID) {
        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    // MARK: - Ping

    /// 发送 ping
    public func ping() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            task?.sendPing { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Internal

    private func startReceiveLoop() {
        guard let task else { return }

        receiveLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { break }
                    let wsMessage: WebSocketMessage
                    switch message {
                    case .string(let text):
                        wsMessage = .text(text)
                    case .data(let data):
                        wsMessage = .data(data)
                    @unknown default:
                        continue
                    }
                    await self.broadcast(wsMessage)
                } catch {
                    if !Task.isCancelled, let self {
                        await self.handleDisconnect(error: error)
                    }
                    break
                }
            }
        }
    }

    private func broadcast(_ message: WebSocketMessage) {
        for (_, continuation) in continuations {
            continuation.yield(message)
        }
    }

    private func handleDisconnect(error: any Error) {
        let reason = error.localizedDescription
        cleanup(reason: reason)

        guard !intentionalDisconnect, autoReconnect, reconnectCount < maxReconnectAttempts else {
            logger.info("WebSocket won't reconnect: intentional=\(self.intentionalDisconnect), count=\(self.reconnectCount)")
            // 终止所有 stream
            for (_, continuation) in continuations {
                continuation.finish()
            }
            continuations.removeAll()
            return
        }

        reconnectCount += 1
        let delay = reconnectBaseDelay * pow(2, Double(reconnectCount - 1))
        logger.info("WebSocket reconnecting (#\(self.reconnectCount)) in \(String(format: "%.1f", delay))s")

        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !self.intentionalDisconnect else { return }
            try? await self.connect()
        }
    }

    private func cleanup(reason: String) {
        state = .disconnected(reason: reason)
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        task = nil
        session?.invalidateAndCancel()
        session = nil
        logger.info("WebSocket disconnected: \(reason)")
    }

    deinit {
        task?.cancel(with: .goingAway, reason: nil)
    }
}
