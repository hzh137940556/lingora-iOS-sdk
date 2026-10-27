// 提供 Tolgee 风格的 Lingora 单例 API，并编排远端、缓存与 Bundle fallback。
import Foundation

/// 管理当前语言、远端翻译和本地回退。
@MainActor
public final class Lingora {
    public static let shared = Lingora()

    public private(set) var isInitialized = false
    public private(set) var lastFetchDate: Date?
    public private(set) var lastFetchSource: LingoraFetchSource?
    public private(set) var loadState: LingoraLoadState = .idle {
        didSet { stateContinuations.values.forEach { $0.yield(loadState) } }
    }

    public private(set) var availableLanguages: [String] = []
    public private(set) var resolvedLanguage: String?
    private var publishedLanguages: [String]?
    private var defaultLanguage: String?
    private var explicitLanguage = false
    private var defaultNamespace: String?
    private var fetchedTables: Set<String> = []
    private var preloadTask: Task<Void, Never>?
    private var configuration: LingoraConfiguration?
    private var currentLocale = Locale.current
    private var currentLanguage: String?
    private var documents: [String: TranslationDocument] = [:]
    private var updateContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var logContinuations: [UUID: AsyncStream<LingoraLogMessage>.Continuation] = [:]
    private var generation: UInt64 = 0
    private var loadLocked = false
    private var loadWaiters: [(UUID, CheckedContinuation<Bool, Never>)] = []
    private var stateContinuations: [UUID: AsyncStream<LingoraLoadState>.Continuation] = [:]
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

    /// 初始化 Content Delivery、语言、namespace 和可选 Bundle JSON 目录；无效配置不启用。
    public func initialize(
        contentDeliveryURL: URL,
        locale: Locale = .current,
        language: String? = nil,
        namespaces: Set<String> = [],
        enableDebugLogs: Bool = false,
        enableSwizzling: Bool = false,
        bundledTranslationsDirectory: String? = nil,
        defaultNamespace: String? = nil,
        availableLanguages: [String]? = nil,
        defaultLanguage: String? = nil
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
        if let defaultNamespace, !Self.isSafePathComponent(defaultNamespace) {
            emit(.error, "Invalid default namespace")
            return
        }
        guard availableLanguages.map(LanguageResolver.validList) ?? true,
              defaultLanguage.map(LanguageResolver.validTag) ?? true else {
            emit(.error, "Invalid language configuration")
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
            namespaces: namespaces.union(defaultNamespace.map { [$0] } ?? []),
            enableDebugLogs: enableDebugLogs
        )
        self.defaultNamespace = defaultNamespace
        self.publishedLanguages = availableLanguages
        self.availableLanguages = availableLanguages ?? []
        self.defaultLanguage = defaultLanguage
        self.bundledTranslationsDirectory = bundledTranslationsDirectory
        explicitLanguage = language != nil
        preloadTask?.cancel()
        preloadTask = nil
        currentLocale = locale
        currentLanguage = resolvedLanguage
        self.resolvedLanguage = nil
        documents = [:]
        fetchedTables = []
        generation &+= 1
        isInitialized = true
        lastFetchDate = nil
        lastFetchSource = nil
        loadState = .idle
        if enableSwizzling {
            BundleSwizzler.enable()
        }
        emit(.debug, "Lingora initialized for language \(resolvedLanguage)")
        restoreCachedDocuments(language: resolvedLanguage, generation: generation)
    }

    /// 获取当前语言或预取指定语言；预取不会切换当前展示语言。
    public func remoteFetch(language: String? = nil) async {
        await fetch(language: language, forceRefresh: true, onlyMissing: false)
    }

    /// 对齐 Android preload：多个消费者共享一次加载，已加载文档不重复请求，失败冷却后可重试。
    public func preload() async {
        guard !Task.isCancelled, let configuration else { return }
        if let task = preloadTask { await task.value; return }
        let tables = Self.tables(for: configuration)
        guard !tables.allSatisfy({ fetchedTables.contains($0) }) else { return }
        let expectedGeneration = generation
        let task = Task { [weak self] in
            guard let self, self.generation == expectedGeneration, !Task.isCancelled else { return }
            await self.fetch(language: nil, forceRefresh: false, onlyMissing: true)
        }
        preloadTask = task
        await task.value
        guard generation == expectedGeneration else { return }
        preloadTask = nil
    }

    /// 合并显式刷新与预加载实现，预加载只补当前缺失的 namespace。
    private func fetch(language: String?, forceRefresh: Bool, onlyMissing: Bool) async {
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
        guard await acquireLoad() else { return }
        defer { releaseLoad() }
        guard !Task.isCancelled, requestedGeneration == generation else { return }
        // 等待其他刷新完成后重新计算缺失项，不让局部预加载使完整刷新失效。
        let tables = Self.tables(for: configuration).filter { !onlyMissing || !fetchedTables.contains($0) }
        if onlyMissing && tables.isEmpty { return }
        if !isPrefetch { loadState = .loading }
        guard let documentLanguage = language != nil || explicitLanguage ? requestedLanguage : matchedLanguage(requestedLanguage) else {
            if !isPrefetch { loadState = .fallback(failedTables: Self.tables(for: configuration)) }
            return
        }
        let store = self.store
        let baseURL = configuration.contentDeliveryURL
        var loaded: [String: (TranslationDocument, LingoraFetchSource)] = [:]
        var cancelled = false
        var failedTables: [String] = []
        await withTaskGroup(of: (String, LoadedDocument).self) { group in
            for table in tables {
                group.addTask {
                    let result = await store.load(
                        baseURL: baseURL,
                        language: documentLanguage,
                        table: table,
                        forceRefresh: forceRefresh
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
                if let warning = result.warning {
                    emit(.warning, warning)
                    if result.source != .network { failedTables.append(table) }
                }
                if let document = result.document, let source = result.source {
                    loaded[table] = (document, source)
                }
            }
        }
        guard !isPrefetch, requestedGeneration == generation,
              requestedLanguage == currentLanguage else { return }
        guard !Task.isCancelled, !cancelled else {
            loadState = .cancelled
            return
        }
        guard !loaded.isEmpty else {
            if onlyMissing, !documents.isEmpty, let source = lastFetchSource {
                loadState = .loaded(source: source, failedTables: failedTables.sorted())
            } else {
                loadState = .fallback(failedTables: failedTables.sorted())
            }
            return
        }
        if resolvedLanguage != documentLanguage { documents = [:] }
        resolvedLanguage = documentLanguage
        fetchedTables.formUnion(loaded.keys)
        documents.merge(loaded.mapValues(\.0)) { _, new in new }
        lastFetchDate = Date()
        lastFetchSource = loaded.values.contains { $0.1 == .network }
            ? .network
            : .cache
        loadState = .loaded(source: lastFetchSource!, failedTables: failedTables.sorted())
        notifyTranslationsUpdated()
        emit(.debug, "Fetched language \(requestedLanguage), tables=\(loaded.count)")
    }

    /// 对齐 Android loadMutex，串行协调整个加载批次及内存提交；等待取消立即退出。
    private func acquireLoad() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            if !loadLocked {
                loadLocked = true
                return true
            }
            return await withCheckedContinuation { loadWaiters.append((id, $0)) }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelLoadWaiter(id) }
        }
    }

    /// 取消尚未取得加载权的请求，不修改正在执行的刷新状态。
    private func cancelLoadWaiter(_ id: UUID) {
        guard let index = loadWaiters.firstIndex(where: { $0.0 == id }) else { return }
        loadWaiters.remove(at: index).1.resume(returning: false)
    }

    /// FIFO 移交加载权；同批次中的 namespace 请求仍可并行。
    private func releaseLoad() {
        if loadWaiters.isEmpty {
            loadLocked = false
        } else {
            loadWaiters.removeFirst().1.resume(returning: true)
        }
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
        let remoteLocale = resolvedLanguage != currentLanguage
            ? resolvedLanguage.map { Locale(identifier: $0) } ?? locale : locale
        if let template = remoteTemplate(
            key,
            arguments: arguments,
            table: table,
            locale: remoteLocale
        ), let rendered = SafeFormatter.render(template, arguments: arguments, locale: remoteLocale) {
            return rendered
        }
        let sdkTable = table ?? defaultNamespace
        if let directory = bundledTranslationsDirectory,
           let template = bundledStore.template(
               for: key,
               bundle: bundle,
               directory: directory,
               language: currentLanguage ?? Self.languageTag(for: locale),
               table: sdkTable?.isEmpty == true ? nil : sdkTable,
               locale: locale,
               arguments: arguments
           ), let rendered = SafeFormatter.render(template, arguments: arguments, locale: locale) {
            return rendered
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
        explicitLanguage = language != nil
        preloadTask?.cancel()
        preloadTask = nil
        currentLocale = locale
        currentLanguage = resolvedLanguage
        self.resolvedLanguage = nil
        documents = [:]
        fetchedTables = []
        generation &+= 1
        lastFetchDate = nil
        lastFetchSource = nil
        loadState = .idle
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

    /// 立即发送当前状态，随后发送加载、成功、部分失败或取消状态。
    public func onLoadStateChanged() -> AsyncStream<LingoraLoadState> {
        let id = UUID()
        return AsyncStream { continuation in
            stateContinuations[id] = continuation
            continuation.yield(loadState)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.stateContinuations[id] = nil }
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

    /// 清空远端内存和当前 App 版本的磁盘缓存，保留不可变 Bundle 资源。
    public func clearCache() throws {
        preloadTask?.cancel()
        preloadTask = nil
        resolvedLanguage = nil
        documents = [:]
        fetchedTables = []
        generation &+= 1
        lastFetchDate = nil
        lastFetchSource = nil
        loadState = .idle
        try store.clear()
        notifyTranslationsUpdated()
    }

    /// 供可选 Bundle swizzling 查询普通远端文本，避免递归进入 fallback。
    func swizzledTranslation(for key: String, table: String?) -> String? {
        guard case .text(let text)? = documents[table ?? defaultNamespace ?? ""]?.values[key] else {
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
        documents[table ?? defaultNamespace ?? ""]?.template(for: key, locale: locale, arguments: arguments)
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
            guard let self else { return }
            guard let documentLanguage = self.explicitLanguage ? language : self.matchedLanguage(language) else { return }
            var cached: [String: TranslationDocument] = [:]
            await withTaskGroup(of: (String, LoadedDocument?).self) { group in
                for table in tables {
                    group.addTask {
                        let result = await store.cached(
                            baseURL: baseURL,
                            language: documentLanguage,
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
            guard !Task.isCancelled,
                  requestedGeneration == self.generation,
                  language == self.currentLanguage,
                  (self.resolvedLanguage == nil || self.resolvedLanguage == documentLanguage),
                  !cached.isEmpty
            else { return }
            let missing = cached.filter { self.documents[$0.key] == nil }
            guard !missing.isEmpty else { return }
            self.resolvedLanguage = documentLanguage
            self.documents.merge(missing) { current, _ in current }
            if self.lastFetchDate == nil {
                self.lastFetchDate = Date()
                self.lastFetchSource = .cache
            }
            if self.loadState == .idle {
                self.loadState = .loaded(source: .cache, failedTables: [])
            }
            self.notifyTranslationsUpdated()
            self.emit(.debug, "Restored language \(language) from cache, tables=\(missing.count)")
        }
    }

    /// 沿用 Android 的候选标签顺序；没有目录时精确请求。
    private func matchedLanguage(_ requested: String) -> String? {
        LanguageResolver.resolve(requested, available: publishedLanguages, defaultLanguage: defaultLanguage)
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
