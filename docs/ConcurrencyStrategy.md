# NetworkKit Concurrency Strategy

```
┌─────────────────────────────────────────────────────────┐
│             NetworkKit 并发模型（三层策略）                 │
├─────────┬───────────────────┬───────────────────────────┤
│  层级    │  机制              │  适用场景                  │
├─────────┼───────────────────┼───────────────────────────┤
│ Tier 1  │ Sendable struct   │ 无状态 / 不可变配置          │
│         │ / enum            │ 零开销，编译器保证安全        │
├─────────┼───────────────────┼───────────────────────────┤
│ Tier 2  │ OSAllocated       │ 简单同步状态保护             │
│         │ UnfairLock        │ 纳秒级，不强迫调用者 async    │
├─────────┼───────────────────┼───────────────────────────┤
│ Tier 3  │ actor             │ 复杂异步生命周期管理          │
│         │                   │ 有 await 开销但管理 async 安全│
└─────────┴───────────────────┴───────────────────────────┘
```

## 选择指南

1. **无可变状态** → Sendable struct / enum（默认选择）
   - Endpoint, HTTPMethod, ParameterEncoding, SessionConfig
   - NetworkClient, UploadClient, 所有无状态 Middleware

2. **少量同步状态** → OSAllocatedUnfairLock\<State\>
   - 优先将所有可变字段合并到单一 State 结构体
   - 避免多锁（防止获取顺序不一致导致的死锁风险）
   - 适用：CircuitBreaker, RequestDeduplicator, MetricsCollector, TokenBucket, RequestContext

3. **复杂异步生命周期** → actor
   - 适用于有 connect/disconnect/receiveLoop 等异步生命周期的对象
   - 适用：WebSocketClient, DownloadTask

## @unchecked Sendable 规则

仅在以下情况使用，且必须在类声明上方注释说明理由：
- (a) class 类型 + 所有可变状态被 OSAllocatedUnfairLock 保护
- (b) 使用 Apple 文档保证线程安全的类型（如 NSCache）
- (c) 存在类型无法被编译器推导的 Sendable 字段（如 `any Sendable`）

## 与 Alamofire 的边界

Alamofire 内部使用 DispatchQueue 管理：
`Session.rootQueue → Session.requestQueue → Session.serializationQueue`

NetworkKit 不触碰这些队列。两者的交互边界是：
`session.request(urlRequest).serializingData().response ← async/await 桥接`

因此不需要"双向映射"——我们的并发模型和 Alamofire 的完全独立。

## 文件对照表

| 文件 | 类型 | 并发机制 | @unchecked? |
|------|------|---------|-------------|
| NetworkClient | struct | 无（不可变） | 否 |
| UploadClient | struct | 无（不可变） | 否 |
| DownloadClient | struct | 无（不可变） | 否 |
| DownloadTask | actor | actor isolation | 否 |
| WebSocketClient | actor | actor isolation | 否 |
| SessionPool | class | 无（init 后不可变） | 否 |
| CircuitBreaker | class | OSAllocatedUnfairLock | 否 |
| RequestDeduplicator | class | OSAllocatedUnfairLock | 否 |
| MetricsCollector | class | OSAllocatedUnfairLock ×2 | 否 |
| TokenBucket | class | OSAllocatedUnfairLock | 否 |
| RequestContext | class | OSAllocatedUnfairLock | 是(a) |
| MockClient | class | OSAllocatedUnfairLock | 是(a) |
| MockResponse | struct | 无 | 是(c) |
| CacheMiddleware | class | NSCache + Lock | 是(a+b) |
| 其他 Middleware | struct | 无（不可变） | 否 |
| 其他 Core 类型 | struct | 无（不可变） | 否 |
