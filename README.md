# NetworkKit

基于 Alamofire 的轻量级类型安全网络层，零业务耦合。

## 特性

- **类型安全 Endpoint** — 泛型绑定请求/响应类型，编译期检查
- **中间件链** — 可插拔的 `Middleware` 协议（签名、认证、重试、日志）
- **Multi-Session 连接池** — 按优先级分流到独立 URLSession（standard / realtime / prefetch）
- **统一错误类型** — `NetworkError` 区分可重试/不可重试，携带 requestID 日志追踪
- **协议抽象** — `RequestSigner`、`ResponseValidatable`、`NetworkClientProtocol` 全面可 Mock

## 要求

- iOS 16+ / macOS 13+
- Swift 6.0
- Alamofire 5.9+

## 安装

### Swift Package Manager

```swift
.package(url: "https://github.com/YourOrg/NetworkKit.git", from: "0.1.0")
```

## 快速使用

```swift
import NetworkKit

// 1. 定义端点
extension Endpoint where Response == MyResponse {
    static func fetchItems(page: Int) -> Endpoint {
        Endpoint(path: "/api/items", parameters: ["page": page])
    }
}

// 2. 发送请求
let client = NetworkClient(
    defaultBaseURL: "https://api.example.com",
    middlewares: [RetryMiddleware(), LogMiddleware()]
)
let response = try await client.send(.fetchItems(page: 1))
```

## 架构

```
NetworkKit/
├── Endpoint.swift          — 类型安全请求描述
├── NetworkClient.swift     — 核心客户端（请求发送 + 中间件编排）
├── NetworkError.swift      — 统一错误类型
├── RequestContext.swift     — 请求上下文（ID + 元数据）
├── ResponseDecoder.swift   — 响应解码 + 自动校验
├── SessionPool.swift       — Multi-Session 连接池
├── HTTPMethod.swift        — HTTP 方法（不暴露 Alamofire）
├── ParameterEncoding.swift — 参数编码方式
├── RequestPriority.swift   — 请求优先级
├── RequestSigner.swift     — 签名协议
└── Middleware/
    ├── Middleware.swift         — 中间件协议 + RecoveryAction
    ├── SigningMiddleware.swift  — 通用签名中间件
    ├── RetryMiddleware.swift    — 指数退避重试
    └── LogMiddleware.swift      — 结构化日志
```

## License

MIT
