// 定义 Lingora SDK 的公开错误、日志和内部配置类型。
import Foundation

/// 表示调用方可处理的 SDK 配置或状态错误。
public enum LingoraError: Error, Equatable, Sendable {
    case sdkNotInitialized
    case unsupportedLocale(String)
}

/// 表示最近一次应用到当前语言的翻译来源。
public enum LingoraFetchSource: Sendable, Equatable {
    case network
    case cache
}

/// 表示 SDK 日志级别。
public enum LingoraLogLevel: String, Sendable {
    case debug
    case warning
    case error
}

/// 表示不包含凭据和响应正文的结构化日志。
public struct LingoraLogMessage: Sendable, Equatable {
    public let level: LingoraLogLevel
    public let message: String
    public let timestamp: Date

    /// 创建一条可供调用方消费的日志。
    public init(level: LingoraLogLevel, message: String, timestamp: Date = Date()) {
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

/// 保存初始化后不可变的公开配置。
struct LingoraConfiguration: Sendable {
    let contentDeliveryURL: URL
    let locale: Locale
    let language: String
    let namespaces: Set<String>
    let enableDebugLogs: Bool
}

/// 表示当前语言最近一次获取的状态；失败不会清除已有翻译。
public enum LingoraLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded(source: LingoraFetchSource, failedTables: [String])
    case fallback(failedTables: [String])
    case cancelled
}
