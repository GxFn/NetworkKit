// MARK: - Upload Client

import Alamofire
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.networkkit", category: "Upload")

/// 上传进度回调
public typealias UploadProgress = @Sendable (UploadState) -> Void

/// 上传状态
public struct UploadState: Sendable {
    /// 已上传字节数
    public let completedBytes: Int64
    /// 总字节数
    public let totalBytes: Int64
    /// 上传进度 0.0 ~ 1.0
    public var fractionCompleted: Double {
        totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
    }

    public init(completedBytes: Int64, totalBytes: Int64) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}

/// 上传结果
public struct UploadResult<Response: Decodable & Sendable>: Sendable {
    /// 服务端返回的解码结果
    public let response: Response
    /// 上传耗时（秒）
    public let elapsed: TimeInterval
}

/// Multipart 表单数据项
public enum MultipartItem: Sendable {
    /// 文件数据
    case data(Data, name: String, fileName: String, mimeType: String)
    /// 文件路径
    case fileURL(URL, name: String, fileName: String, mimeType: String)
    /// 文本字段
    case text(String, name: String)
}

/// 上传客户端
///
/// 支持 multipart/form-data 上传和原始 Data 上传。
///
/// ```swift
/// let client = UploadClient()
///
/// // Multipart 上传
/// let result: UploadResult<UploadResponse> = try await client.multipart(
///     to: URL(string: "https://api.example.com/upload")!,
///     items: [
///         .data(imageData, name: "file", fileName: "avatar.jpg", mimeType: "image/jpeg"),
///         .text("avatar", name: "type")
///     ]
/// ) { state in
///     print("Upload: \(Int(state.fractionCompleted * 100))%")
/// }
///
/// // 原始 Data 上传
/// let result: UploadResult<Response> = try await client.upload(
///     data: jsonData,
///     to: url,
///     method: .put,
///     headers: ["Content-Type": "application/octet-stream"]
/// )
/// ```
public struct UploadClient: Sendable {

    private let sessionPool: SessionPool
    private let decoder: ResponseDecoder

    public init(sessionPool: SessionPool = .shared, decoder: ResponseDecoder = .default) {
        self.sessionPool = sessionPool
        self.decoder = decoder
    }

    // MARK: - Multipart Upload

    /// Multipart 表单上传
    public func multipart<T: Decodable & Sendable>(
        to url: URL,
        items: [MultipartItem],
        method: HTTPMethod = .post,
        headers: [String: String]? = nil,
        progress: UploadProgress? = nil
    ) async throws -> UploadResult<T> {
        let httpHeaders = headers.map { dict in
            HTTPHeaders(dict.map { HTTPHeader(name: $0.key, value: $0.value) })
        }

        let request = sessionPool.session(for: .upload).upload(
            multipartFormData: { formData in
                for item in items {
                    switch item {
                    case .data(let data, let name, let fileName, let mimeType):
                        formData.append(data, withName: name, fileName: fileName, mimeType: mimeType)
                    case .fileURL(let fileURL, let name, let fileName, let mimeType):
                        formData.append(fileURL, withName: name, fileName: fileName, mimeType: mimeType)
                    case .text(let value, let name):
                        if let data = value.data(using: .utf8) {
                            formData.append(data, withName: name)
                        }
                    }
                }
            },
            to: url,
            method: method.alamofire,
            headers: httpHeaders
        )

        return try await trackAndDecode(request: request, url: url, progress: progress)
    }

    // MARK: - Raw Data Upload

    /// 原始数据上传
    public func upload<T: Decodable & Sendable>(
        data uploadData: Data,
        to url: URL,
        method: HTTPMethod = .put,
        headers: [String: String]? = nil,
        progress: UploadProgress? = nil
    ) async throws -> UploadResult<T> {
        let httpHeaders = headers.map { dict in
            HTTPHeaders(dict.map { HTTPHeader(name: $0.key, value: $0.value) })
        }

        let request = sessionPool.session(for: .upload).upload(
            uploadData,
            to: url,
            method: method.alamofire,
            headers: httpHeaders
        )

        return try await trackAndDecode(request: request, url: url, progress: progress)
    }

    // MARK: - Private

    /// 统一的进度追踪 + 响应处理 + 解码流程
    private func trackAndDecode<T: Decodable & Sendable>(
        request: UploadRequest,
        url: URL,
        progress: UploadProgress?
    ) async throws -> UploadResult<T> {
        let startTime = Date()
        let requestID = UUID().uuidString

        if let progress {
            request.uploadProgress { p in
                progress(UploadState(
                    completedBytes: p.completedUnitCount,
                    totalBytes: p.totalUnitCount
                ))
            }
        }

        // 使用 Alamofire .validate() + 原生 async API
        let response = await request
            .validate(statusCode: 200..<300)
            .serializingData()
            .response

        if let afError = response.error {
            throw NetworkError.from(
                afError: afError,
                response: response.response,
                data: response.data,
                requestID: requestID
            )
        }

        guard let data = response.data else {
            throw NetworkError.transport(
                underlying: URLError(.badServerResponse),
                requestID: requestID
            )
        }

        let context = RequestContext(id: requestID, path: url.path)
        let decoded: T = try decoder.decode(T.self, from: data, context: context)
        let elapsed = Date().timeIntervalSince(startTime)

        logger.info("[\(requestID.prefix(8))] Upload complete → \(url.lastPathComponent) (\(String(format: "%.0f", elapsed * 1000))ms)")

        return UploadResult(response: decoded, elapsed: elapsed)
    }
}
