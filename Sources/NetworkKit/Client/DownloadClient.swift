// MARK: - Download Task

import Alamofire
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Download")

/// 下载进度回调
public typealias DownloadProgress = @Sendable (DownloadState) -> Void

/// 下载状态
public struct DownloadState: Sendable {
    /// 已下载字节数
    public let completedBytes: Int64
    /// 文件总字节数（未知时为 nil）
    public let totalBytes: Int64?
    /// 下载进度 0.0 ~ 1.0（总大小未知时为 nil）
    public let fractionCompleted: Double?

    public init(completedBytes: Int64, totalBytes: Int64?) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.fractionCompleted = totalBytes.map { total in
            total > 0 ? Double(completedBytes) / Double(total) : 0
        }
    }
}

/// 下载结果
public struct DownloadResult: Sendable {
    /// 下载后的文件路径
    public let fileURL: URL
    /// 文件大小（字节）
    public let fileSize: Int64
}

/// 断点续传下载客户端
///
/// 基于 Alamofire 的 download + resumeData 实现。
/// - 自动管理 resumeData 持久化
/// - 支持暂停/恢复/取消
/// - 通过 `DownloadProgress` 回调实时进度
///
/// ```swift
/// let client = DownloadClient()
///
/// // 开始下载
/// let task = client.download(
///     url: videoURL,
///     to: cacheDir.appending(path: "video.mp4")
/// ) { state in
///     print("Progress: \(state.fractionCompleted ?? 0)")
/// }
///
/// // 暂停（自动保存 resumeData）
/// await task.pause()
///
/// // 恢复
/// await task.resume()
///
/// // 等待完成
/// let result = try await task.result
/// ```
public final class DownloadClient: Sendable {

    private let session: Session

    public init(session: Session? = nil) {
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.httpMaximumConnectionsPerHost = 3
            config.timeoutIntervalForResource = 600
            return Session(configuration: config)
        }()
    }

    /// 创建下载任务
    ///
    /// - Parameters:
    ///   - url: 远程文件 URL
    ///   - destination: 本地保存路径
    ///   - headers: 额外请求头
    ///   - progress: 进度回调（非主线程）
    /// - Returns: 可控制的下载任务句柄
    public func download(
        url: URL,
        to destination: URL,
        headers: [String: String]? = nil,
        progress: DownloadProgress? = nil
    ) -> DownloadTask {
        let resumeDataURL = Self.resumeDataURL(for: url, destination: destination)
        return DownloadTask(
            remoteURL: url,
            destination: destination,
            resumeDataURL: resumeDataURL,
            headers: headers,
            session: session,
            progress: progress
        )
    }

    // MARK: - Resume Data Path

    /// resumeData 存储路径：基于 URL + destination 的 hash
    private static func resumeDataURL(for url: URL, destination: URL) -> URL {
        let key = "\(url.absoluteString)|\(destination.path)".data(using: .utf8)!
        let hash = key.withUnsafeBytes { buffer -> String in
            var result: UInt64 = 14695981039346656037  // FNV-1a offset basis
            for byte in buffer {
                result ^= UInt64(byte)
                result &*= 1099511628211  // FNV prime
            }
            return String(result, radix: 16)
        }

        let dir = FileManager.default.temporaryDirectory.appending(path: "networkkit-downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(hash).resume")
    }
}

// MARK: - Download Task

/// 可控制的下载任务
///
/// 支持 pause / resume / cancel，暂停时自动持久化 resumeData。
public final actor DownloadTask {

    private let remoteURL: URL
    private let destination: URL
    private let resumeDataURL: URL
    private let headers: [String: String]?
    private let session: Session
    private let progress: DownloadProgress?

    private var downloadRequest: DownloadRequest?
    private var continuation: CheckedContinuation<DownloadResult, any Error>?
    private var state: TaskState = .idle

    private enum TaskState {
        case idle, downloading, paused, completed, cancelled, failed
    }

    init(
        remoteURL: URL,
        destination: URL,
        resumeDataURL: URL,
        headers: [String: String]?,
        session: Session,
        progress: DownloadProgress?
    ) {
        self.remoteURL = remoteURL
        self.destination = destination
        self.resumeDataURL = resumeDataURL
        self.headers = headers
        self.session = session
        self.progress = progress
    }

    /// 等待下载完成
    public var result: DownloadResult {
        get async throws {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.startOrResume()
            }
        }
    }

    /// 暂停下载（保存 resumeData 以便续传）
    public func pause() {
        guard state == .downloading, let request = downloadRequest else { return }
        state = .paused
        request.cancel(producingResumeData: true)
        logger.info("Download paused: \(self.remoteURL.lastPathComponent)")
    }

    /// 恢复下载
    public func resume() {
        guard state == .paused else { return }
        startOrResume()
    }

    /// 取消下载（清理 resumeData）
    public func cancel() {
        state = .cancelled
        downloadRequest?.cancel()
        cleanResumeData()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        logger.info("Download cancelled: \(self.remoteURL.lastPathComponent)")
    }

    // MARK: - Internal

    private func startOrResume() {
        state = .downloading

        let afDestination: DownloadRequest.Destination = { [destination] _, _ in
            (destination, [.removePreviousFile, .createIntermediateDirectories])
        }

        let request: DownloadRequest

        // 检查是否有 resumeData
        if let resumeData = loadResumeData() {
            request = session.download(resumingWith: resumeData, to: afDestination)
            logger.info("Download resuming: \(self.remoteURL.lastPathComponent) (\(resumeData.count) bytes resume data)")
        } else {
            var httpHeaders: HTTPHeaders?
            if let headers {
                httpHeaders = HTTPHeaders(headers.map { HTTPHeader(name: $0.key, value: $0.value) })
            }
            request = session.download(remoteURL, headers: httpHeaders, to: afDestination)
            logger.info("Download starting: \(self.remoteURL.lastPathComponent)")
        }

        // 进度回调
        if let progress {
            request.downloadProgress { p in
                let state = DownloadState(
                    completedBytes: p.completedUnitCount,
                    totalBytes: p.totalUnitCount > 0 ? p.totalUnitCount : nil
                )
                progress(state)
            }
        }

        // 完成回调
        request.response { [weak self] response in
            guard let self else { return }
            Task { await self.handleCompletion(response) }
        }

        self.downloadRequest = request
    }

    private func handleCompletion(_ response: AFDownloadResponse<URL?>) {
        switch state {
        case .cancelled:
            return  // 已处理

        case .downloading, .paused:
            if let error = response.error {
                // 暂停产生的取消 → 保存 resumeData
                if let resumeData = response.resumeData, state == .paused || error.isExplicitlyCancelledError {
                    saveResumeData(resumeData)
                    // paused 状态不 resume continuation，等 resume() 调用
                    if state == .paused { return }
                }

                state = .failed
                let networkError = NetworkError.transport(
                    underlying: error,
                    requestID: UUID().uuidString
                )
                continuation?.resume(throwing: networkError)
                continuation = nil
                logger.error("Download failed: \(self.remoteURL.lastPathComponent) — \(error.localizedDescription)")
                return
            }

            guard let fileURL = response.fileURL else {
                state = .failed
                let error = NetworkError.transport(
                    underlying: URLError(.cannotCreateFile),
                    requestID: UUID().uuidString
                )
                continuation?.resume(throwing: error)
                continuation = nil
                return
            }

            // 成功
            state = .completed
            cleanResumeData()

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            let result = DownloadResult(fileURL: fileURL, fileSize: fileSize)
            continuation?.resume(returning: result)
            continuation = nil
            logger.info("Download complete: \(self.remoteURL.lastPathComponent) (\(fileSize) bytes)")

        default:
            break
        }
    }

    // MARK: - Resume Data Persistence

    private func saveResumeData(_ data: Data) {
        do {
            try data.write(to: resumeDataURL, options: .atomic)
            logger.debug("Resume data saved: \(data.count) bytes")
        } catch {
            logger.warning("Failed to save resume data: \(error.localizedDescription)")
        }
    }

    private func loadResumeData() -> Data? {
        guard FileManager.default.fileExists(atPath: resumeDataURL.path) else { return nil }
        return try? Data(contentsOf: resumeDataURL)
    }

    private func cleanResumeData() {
        try? FileManager.default.removeItem(at: resumeDataURL)
    }
}
