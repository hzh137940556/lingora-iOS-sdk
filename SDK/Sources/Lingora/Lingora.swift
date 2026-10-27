// 提供 Tolgee 风格的 Lingora 单例 API，并编排远端、缓存与 Bundle fallback。
import Foundation

/// 管理当前语言、远端翻译和本地回退。
@MainActor
public final class Lingora {
    public static let shared = Lingora()

    public private(set) var isInitialized = false
    public private(set) var lastFetchDate: Date?
    public private(set) var lastFetchSource: LingoraFetchSource?

    private var configuration: LingoraConfiguration?
    private var currentLocale = Locale.current
    private var currentLanguage: String?
    private var documents: [String: TranslationDocument] = [:]
    private var updateContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var logContinuations: [UUID: AsyncStream<LingoraLogMessage>.Continuation] = [:]
    private var generation: UInt64 = 0
    private let store: ContentDeliveryStore
    private let bundledStore = BundledTranslationStore()
    private var bundledTranslationsDirectory: String?

    /// 创建共享实例或可注入依赖的测试实例。
    init(
        session: URLSession = .shared,
        cacheDirectory: URL? = nil,
        appVersion: String? = nil
    ) {
        let directory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lingora", isDirectory: true)
        let version = appVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "1"
        store = ContentDeliveryStore(
            cacheDirectory: directory,
            session: session,
            appVersion: version
        )
    }

    /// 初始化 Content Delivery、语言和 namespace；无效配置保持未初始化状态。
    public func initialize(
        contentDeliveryURL: URL,
        locale: Locale = .current,
        language: String? = nil,
        namespaces: Set<String> = [],
        enableDebugLogs: Bool = false,
        enableSwizzling: Bool = false,
        bundledTranslationsDirectory: String? = nil
    ) {
        guard configuration == nil else {
            emit(.debug, "Repeated initialize call was ignored")
            return
        }
        guard Self.isSafeHTTPURL(contentDeliveryURL) else {
            emit(.error, "Content Delivery URL must be a credential-free HTTP(S) URL")
            return
        }
        if let directory = bundledTranslationsDirectory, !Self.isSafePathComponent(directory) {
            emit(.error, "Bundled translation directory must be a safe path component")
            return
        }
        let resolvedLanguage = language ?? Self.languageTag(for: locale)
        guard Self.isSafePathComponent(resolvedLanguage),
              namespaces.allSatisfy({ Self.isSafePathComponent($0) })
        else {
            emit(.error, "Language and namespaces must be safe path components")
            return
        }
        configuration = LingoraConfiguration(
            contentDeliveryURL: contentDeliveryURL,
            locale: locale,
            language: resolvedLanguage,
            namespaces: namespaces,
            enableDebugLogs: enableDebugLogs
        )
        self.bundledTranslationsDirectory = bundledTranslationsDirectory
        currentLocale = locale
        currentLanguage = resolvedLanguage
        documents = [:]
        generation &+= 1
        isInitialized = true
        lastFetchDate = nil
        lastFetchSource = nil
        if enableSwizzling {
            BundleSwizzler.enable()
        }
        emit(.debug, "Lingora initialized for language \(resolvedLanguage)")
        restoreCachedDocuments(language: resolvedLanguage, generation: generation)
    }

    /// 获取当前语言或预取指定语言；预取不会切换当前展示语言。
    public func remoteFetch(language: String? = nil) async {
        guard let configuration, let activeLanguage = currentLanguage else {
            emit(.error, "Lingora must be initialized before remoteFetch")
            return
        }
        let requestedLanguage = language ?? activeLanguage
        let isPrefetch = language != nil && requestedLanguage != activeLanguage
        guard Self.isSafePathComponent(requestedLanguage) else {
            emit(.error, "Fetch language must be a safe path component")
            return
        }
        let requestedGeneration = generation
        let tables = Self.tables(for: configuration)
        let store = self.store
        let baseURL = configuration.contentDeliveryURL
        var loaded: [String: (TranslationDocument, LingoraFetchSource)] = [:]
        var cancelled = false
        await withTaskGroup(of: (String, LoadedDocument).self) { group in
            for table in tables {
                group.addTask {
                    let result = await store.load(
                        baseURL: baseURL,
                        language: requestedLanguage,
                        table: table
                    )
                    return (table, result)
                }
            }
            for await (table, result) in group {
                if result.isCancelled || Task.isCancelled {
                    cancelled = true
                    group.cancelAll()
                    continue
                }
                if let warning = result.warning { emit(.warning, warning) }
                if let document = result.document, let source = result.source {
                    loaded[table] = (document, source)
                }
            }
        }
        guard !Task.isCancelled, !cancelled else { return }
        guard !isPrefetch,
              requestedGeneration == generation,
              requestedLanguage == currentLanguage,
              !loaded.isEmpty
        else {
            emit(.debug, "Prefetched language \(requestedLanguage), tables=\(loaded.count)")
            return
        }
        documents.merge(loaded.mapValues(\.0)) { _, new in new }
        lastFetchDate = Date()
        lastFetchSource = loaded.values.contains { $0.1 == .network }
            ? .network
            : .cache
        notifyTranslationsUpdated()
        emit(.debug, "Fetched language \(requestedLanguage), tables=\(loaded.count)")
    }

    /// 依次查找远端、可选 Bundle JSON 和指定 Bundle/Table 的系统资源。
    public func translate(
        _ key: String,
        _ arguments: CVarArg...,
        table: String? = nil,
        bundle: Bundle = .main,
        locale providedLocale: Locale = .current
    ) -> String {
        translateValue(
            key,
            arguments: arguments,
            table: table,
            bundle: bundle,
            locale: providedLocale
        )
    }

    /// 为 SwiftUI 包装器复用数组形式的格式化参数。
    func translateValue(
        _ key: String,
        arguments: [CVarArg],
        table: String?,
        bundle: Bundle,
        locale providedLocale: Locale
    ) -> String {
        let locale = currentLocale == .current ? providedLocale : currentLocale
        if let template = remoteTemplate(
            key,
            arguments: arguments,
            table: table,
            locale: locale
        ) {
            return Self.render(template, arguments: arguments, locale: locale)
        }
        if let directory = bundledTranslationsDirectory,
           let template = bundledStore.template(
               for: key,
               bundle: bundle,
               directory: directory,
               language: currentLanguage ?? Self.languageTag(for: locale),
               table: table,
               locale: locale,
               arguments: arguments
           ) {
            return Self.render(template, arguments: arguments, locale: locale)
        }
        let fallback = Self.localizedString(
            forKey: key,
            table: table,
            locale: locale,
            in: bundle
        ) ?? key
        return Self.render(fallback, arguments: arguments, locale: locale)
    }

    /// 切换 locale 和可选 CDN language；显式 language 允许仅远端存在的语言。
    public func setCustomLocale(_ locale: Locale, language: String? = nil) throws {
        guard configuration != nil else { throw LingoraError.sdkNotInitialized }
        let resolvedLanguage = language ?? Self.languageTag(for: locale)
        guard Self.isSafePathComponent(resolvedLanguage) else {
            throw LingoraError.unsupportedLocale(locale.identifier)
        }
        if language == nil, locale != .current,
           Self.localizedBundle(for: locale, in: .main) == nil {
            throw LingoraError.unsupportedLocale(locale.identifier)
        }
        currentLocale = locale
        currentLanguage = resolvedLanguage
        documents = [:]
        generation &+= 1
        lastFetchDate = nil
        lastFetchSource = nil
        notifyTranslationsUpdated()
        restoreCachedDocuments(language: resolvedLanguage, generation: generation)
    }

    /// 订阅远端文档或语言切换后的刷新事件。
    public func onTranslationsUpdated() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            updateContinuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.updateContinuations[id] = nil }
            }
        }
    }

    /// 订阅不含凭据和响应正文的结构化日志。
    public func onLogMessage() -> AsyncStream<LingoraLogMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            logContinuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.logContinuations[id] = nil }
            }
        }
    }

    /// 清空内存和当前 App 版本的磁盘缓存。
    public func clearCache() throws {
        documents = [:]
        generation &+= 1
        lastFetchDate = nil
        lastFetchSource = nil
        try store.clear()
        notifyTranslationsUpdated()
    }

    /// 供可选 Bundle swizzling 查询普通远端文本，避免递归进入 fallback。
    func swizzledTranslation(for key: String, table: String?) -> String? {
        guard case .text(let text)? = documents[table ?? ""]?.values[key] else {
            return nil
        }
        return text
    }

    /// 从当前 table 文档读取并选择模板。
    private func remoteTemplate(
        _ key: String,
        arguments: [CVarArg],
        table: String?,
        locale: Locale
    ) -> String? {
        documents[table ?? ""]?.template(for: key, locale: locale, arguments: arguments)
    }

    /// 发送翻译更新事件。
    private func notifyTranslationsUpdated() {
        updateContinuations.values.forEach { $0.yield(()) }
    }

    /// 初始化或切换语言后异步恢复当前 language/table 的有效磁盘缓存。
    private func restoreCachedDocuments(language: String, generation requestedGeneration: UInt64) {
        guard let configuration else { return }
        let tables = Self.tables(for: configuration)
        let baseURL = configuration.contentDeliveryURL
        let store = self.store
        Task { [weak self] in
            var cached: [String: TranslationDocument] = [:]
            await withTaskGroup(of: (String, LoadedDocument?).self) { group in
                for table in tables {
                    group.addTask {
                        let result = await store.cached(
                            baseURL: baseURL,
                            language: language,
                            table: table
                        )
                        return (table, result)
                    }
                }
                for await (table, result) in group {
                    if let document = result?.document {
                        cached[table] = document
                    }
                }
            }
            guard let self,
                  !Task.isCancelled,
                  requestedGeneration == self.generation,
                  language == self.currentLanguage,
                  !cached.isEmpty
            else { return }
            let missing = cached.filter { self.documents[$0.key] == nil }
            guard !missing.isEmpty else { return }
            self.documents.merge(missing) { current, _ in current }
            if self.lastFetchDate == nil {
                self.lastFetchDate = Date()
                self.lastFetchSource = .cache
            }
            self.notifyTranslationsUpdated()
            self.emit(.debug, "Restored language \(language) from cache, tables=\(missing.count)")
        }
    }

    /// 根据日志级别和 debug 开关发送结构化日志。
    private func emit(_ level: LingoraLogLevel, _ message: String) {
        if level == .debug, configuration?.enableDebugLogs != true { return }
        let event = LingoraLogMessage(level: level, message: message)
        logContinuations.values.forEach { $0.yield(event) }
    }

    /// 格式化普通或 plural 模板，无参数时保持原文。
    private static func render(
        _ template: String,
        arguments: [CVarArg],
        locale: Locale
    ) -> String {
        arguments.isEmpty
            ? template
            : String(format: template, locale: locale, arguments: arguments)
    }

    /// 将 Locale 转为 Content Delivery 使用的 BCP-47 风格标签。
    private static func languageTag(for locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-")
    }

    /// 空 namespace 集合使用根文档，否则每个 namespace 对应具名 table。
    private static func tables(for configuration: LingoraConfiguration) -> [String] {
        configuration.namespaces.isEmpty ? [""] : configuration.namespaces.sorted()
    }

    /// 选择当前 Bundle 中最具体的 locale 资源。
    private static func localizedBundle(for locale: Locale, in bundle: Bundle) -> Bundle? {
        let parts = locale.identifier.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
        for length in stride(from: parts.count, through: 1, by: -1) {
            let tag = parts.prefix(length).joined(separator: "-")
            if let path = bundle.path(forResource: tag, ofType: "lproj"),
               let localized = Bundle(path: path) {
                return localized
            }
        }
        return nil
    }

    /// 按“完整 locale → 基础语言 → Bundle 默认语言”查找本地文案，跳过空目录或缺失 key。
    private static func localizedString(
        forKey key: String,
        table: String?,
        locale: Locale,
        in bundle: Bundle
    ) -> String? {
        let missingValue = "\u{F8FF}Lingora.Missing.\(key)"
        let parts = locale.identifier.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
        for length in stride(from: parts.count, through: 1, by: -1) {
            let tag = parts.prefix(length).joined(separator: "-")
            guard let path = bundle.path(forResource: tag, ofType: "lproj"),
                  let localized = Bundle(path: path)
            else { continue }
            let value = localized.localizedString(
                forKey: key,
                value: missingValue,
                table: table
            )
            if value != missingValue { return value }
        }
        let value = bundle.localizedString(forKey: key, value: missingValue, table: table)
        return value == missingValue ? nil : value
    }

    /// 拒绝路径穿越或空语言/namespace。
    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && value.range(
                of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$",
                options: .regularExpression
            ) != nil
    }

    /// 拒绝非 HTTP(S)、内嵌凭据和 query/fragment。
    private static func isSafeHTTPURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        return ["http", "https"].contains(components.scheme)
            && components.host != nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
    }
}
