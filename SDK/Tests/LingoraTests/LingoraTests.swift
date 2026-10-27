// 验证 Lingora 公开 API 的网络、缓存、格式化和失败回退。
import Foundation
import XCTest
@testable import Lingora

/// 提供不访问外网的 URLSession 响应。
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// 描述一次可重复消费的模拟 HTTP 响应。
    struct Response {
        let status: Int
        let headers: [String: String]
        let data: Data
        let delay: TimeInterval

        /// 创建一条可选延迟的模拟响应。
        init(
            status: Int,
            headers: [String: String],
            data: Data,
            delay: TimeInterval = 0
        ) {
            self.status = status
            self.headers = headers
            self.data = data
            self.delay = delay
        }
    }

    nonisolated(unsafe) static var responses: [Response] = []
    nonisolated(unsafe) static var responsesByPath: [String: [Response]] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var error: Error?
    private static let lock = NSLock()
    private let responseLock = NSLock()
    private var responseWork: DispatchWorkItem?

    /// 在锁内读取请求数，供异步并发测试等待网络开始。
    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    /// 接受所有测试请求。
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// 不重写测试请求。
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// 同步返回测试注册的响应。
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let error = Self.error
        let path = request.url?.path ?? ""
        let item: Response? = {
            if var pathResponses = Self.responsesByPath[path], !pathResponses.isEmpty {
                let response = pathResponses.removeFirst()
                Self.responsesByPath[path] = pathResponses
                return response
            }
            guard !Self.responses.isEmpty else { return nil }
            return Self.responses.removeFirst()
        }()
        Self.lock.unlock()
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let item else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let work = DispatchWorkItem { [self] in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: item.status,
                httpVersion: "HTTP/1.1", headerFields: item.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: item.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        responseLock.lock()
        responseWork = work
        responseLock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + item.delay, execute: work)
    }

    /// 取消尚未发送的延迟响应，允许真实模拟乱序网络完成。
    override func stopLoading() {
        responseLock.lock()
        responseWork?.cancel()
        responseLock.unlock()
    }

}

/// 覆盖主线程公开 API 和 Content Delivery 行为。
@MainActor
final class LingoraTests: XCTestCase {
    nonisolated(unsafe) private var temporary: URL!

    /// 为每个测试创建独立缓存并重置网络处理器。
    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        MockURLProtocol.responses = []
        MockURLProtocol.responsesByPath = [:]
        MockURLProtocol.requests = []
        MockURLProtocol.error = nil
    }

    /// 清理测试缓存和全局响应。
    override func tearDownWithError() throws {
        MockURLProtocol.responses = []
        MockURLProtocol.responsesByPath = [:]
        MockURLProtocol.requests = []
        MockURLProtocol.error = nil
        try? FileManager.default.removeItem(at: temporary)
    }

    /// namespace URL、远端格式化和 ETag/304 缓存必须形成闭环。
    func testFetchTranslateAndConditionalCache() async throws {
        let session = makeSession()
        MockURLProtocol.responses = [
            .init(
                status: 200,
                headers: ["ETag": "v1"],
                data: Data(
                    #"{"welcome":"Hello %@","items":{"variations":{"plural":{"one":"%lld item","other":"%lld items"}}}}"#.utf8
                )
            ),
            .init(status: 304, headers: [:], data: Data()),
        ]
        let lingora = Lingora(
            session: session,
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com/release")!,
            locale: Locale(identifier: "en-US"),
            language: "en-US",
            namespaces: ["app"]
        )
        XCTAssertTrue(lingora.isInitialized)
        await lingora.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, "/release/app/en-US.json")
        XCTAssertEqual(
            lingora.translate("welcome", "Lingora", table: "app"),
            "Hello Lingora"
        )
        XCTAssertEqual(lingora.translate("items", Int64(2), table: "app"), "2 items")
        XCTAssertEqual(lingora.lastFetchSource, .network)
        XCTAssertNotNil(lingora.lastFetchDate)

        await lingora.remoteFetch()
        XCTAssertEqual(
            MockURLProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match"),
            "v1"
        )
        XCTAssertEqual(lingora.translate("welcome", "Cache", table: "app"), "Hello Cache")
        XCTAssertEqual(lingora.lastFetchSource, .cache)
    }

    /// 瞬时错误重试一次，并在后续离线实例中使用磁盘缓存。
    func testRetryAndOfflineCacheFallback() async throws {
        let session = makeSession()
        MockURLProtocol.responses = [
            .init(status: 503, headers: [:], data: Data()),
            .init(
                status: 200,
                headers: ["ETag": "v2"],
                data: Data(#"{"welcome":"Remote"}"#.utf8)
            ),
        ]
        let online = Lingora(
            session: session,
            cacheDirectory: temporary,
            appVersion: "1"
        )
        online.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            locale: Locale(identifier: "en"),
            language: "en"
        )
        await online.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertEqual(online.translate("welcome"), "Remote")

        MockURLProtocol.error = URLError(.notConnectedToInternet)
        let offline = Lingora(
            session: session,
            cacheDirectory: temporary,
            appVersion: "1"
        )
        offline.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            locale: Locale(identifier: "en"),
            language: "en"
        )
        await offline.remoteFetch()
        XCTAssertEqual(offline.translate("welcome"), "Remote")
        try offline.clearCache()
    }

    /// 永久 HTTP 错误和取消不得触发第二次请求。
    func testPermanentFailureAndCancellationAreNotRetried() async {
        let session = makeSession()
        let lingora = Lingora(
            session: session,
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en-US",
            namespaces: ["app"]
        )

        MockURLProtocol.responses = [
            .init(status: 404, headers: [:], data: Data()),
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"wrong"}"#.utf8)),
        ]
        await lingora.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        MockURLProtocol.requests = []
        MockURLProtocol.responses = []
        MockURLProtocol.error = URLError(.cancelled)
        await lingora.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    /// 预取不得切换当前语言，显式 CDN language 可以切换远端专有语言。
    func testPrefetchAndCustomLocale() async throws {
        let session = makeSession()
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"ja"}"#.utf8)),
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"ja"}"#.utf8)),
        ]
        let lingora = Lingora(
            session: session,
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            locale: Locale(identifier: "en"),
            language: "en"
        )
        await lingora.remoteFetch(language: "ja")
        XCTAssertEqual(lingora.translate("welcome"), "welcome")
        try lingora.setCustomLocale(Locale(identifier: "ja"), language: "ja")
        await lingora.remoteFetch()
        XCTAssertEqual(lingora.translate("welcome"), "ja")
    }

    /// 精确 locale 目录为空时，Bundle fallback 必须继续读取基础语言资源。
    func testBundleFallbackContinuesFromRegionToBaseLanguage() throws {
        let bundleURL = temporary.appendingPathComponent("Fallback.bundle", isDirectory: true)
        let regionalURL = bundleURL.appendingPathComponent("en-US.lproj", isDirectory: true)
        let languageURL = bundleURL.appendingPathComponent("en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(
            at: regionalURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: languageURL,
            withIntermediateDirectories: true
        )
        let info: [String: String] = [
            "CFBundleIdentifier": "io.lingora.tests.fallback",
            "CFBundleDevelopmentRegion": "en",
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: bundleURL.appendingPathComponent("Info.plist"))
        try #""demo_title" = "Lingora dynamic text test";"#.write(
            to: languageURL.appendingPathComponent("app.strings"),
            atomically: true,
            encoding: .utf8
        )
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))
        let lingora = Lingora(
            session: makeSession(),
            cacheDirectory: temporary.appendingPathComponent("cache"),
            appVersion: "1"
        )

        XCTAssertEqual(
            lingora.translate(
                "demo_title",
                table: "app",
                bundle: bundle,
                locale: Locale(identifier: "en-US")
            ),
            "Lingora dynamic text test"
        )
    }

    /// 创建同时含原生资源和 SDK JSON 的独立资源 Bundle。
    private func makeJSONBundle(_ files: [String: String]) throws -> Bundle {
        let root = temporary.appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "io.lingora.tests." + UUID().uuidString,
                    "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        return try XCTUnwrap(Bundle(url: root))
    }

    /// 无网络也能格式化 Bundle JSON，按语言和 namespace 隔离并回退到原生资源。
    func testBundledJSONOfflineAndLocaleFallback() async throws {
        let bundle = try makeJSONBundle([
            "Lingora/app/ja.json": #"{"hello":"こんにちは %@","items":{"variations":{"plural":{"other":"%lld 個"}}}}"#,
            "Lingora/app/en.json": #"{"default":"Development","englishOnly":{"variations":{"plural":{"one":"%lld item","other":"%lld items"}}},"items":{"variations":{"plural":{"one":"%lld item","other":"%lld items"}}}}"#,
            "Lingora/common/ja.json": #"{"hello":"Common %@"}"#,
            "Lingora/ja.json": #"{"hello":"Default table"}"#,
            "en.lproj/app.strings": #""native" = "Native";"#,
        ])
        let lingora = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("cache"))
        lingora.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!,
                           locale: Locale(identifier: "ja-JP"), language: "ja-JP", namespaces: ["app", "common"],
                           bundledTranslationsDirectory: "Lingora")
        XCTAssertEqual(lingora.translate("hello", "iOS", table: "app", bundle: bundle), "こんにちは iOS")
        XCTAssertEqual(lingora.translate("hello", "iOS", table: "common", bundle: bundle), "Common iOS")
        XCTAssertEqual(lingora.translate("hello", bundle: bundle), "Default table")
        XCTAssertEqual(lingora.translate("items", Int64(3), table: "app", bundle: bundle), "3 個")
        XCTAssertEqual(lingora.translate("default", table: "app", bundle: bundle), "Development")
        XCTAssertEqual(lingora.translate("englishOnly", Int64(1), table: "app", bundle: bundle), "1 item")
        XCTAssertEqual(lingora.translate("native", table: "app", bundle: bundle), "Native")
        XCTAssertEqual(lingora.translate("missing", table: "app", bundle: bundle), "missing")
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        await lingora.remoteFetch()
        XCTAssertNil(lingora.lastFetchSource)
        XCTAssertEqual(lingora.translate("hello", "offline", table: "app", bundle: bundle), "こんにちは offline")
        try lingora.setCustomLocale(Locale(identifier: "en"), language: "en")
        XCTAssertEqual(lingora.translate("items", Int64(1), table: "app", bundle: bundle), "1 item")
        XCTAssertEqual(lingora.translate("items", Int64(2), table: "app", bundle: bundle), "2 items")
    }

    /// 远端优先、缺失 Key 使用 JSON，并保持调用方 Bundle 隔离和清缓存后的离线资源。
    func testBundledJSONRemotePrecedenceAndBundleIsolation() async throws {
        let first = try makeJSONBundle(["Lingora/app/en.json": #"{"hello":"First","local":"Local"}"#])
        let second = try makeJSONBundle(["Lingora/app/en.json": #"{"hello":"Second"}"#])
        let lingora = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("cache"))
        lingora.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!,
                           locale: Locale(identifier: "en"), language: "en", namespaces: ["app"],
                           bundledTranslationsDirectory: "Lingora")
        XCTAssertEqual(lingora.translate("hello", table: "app", bundle: first), "First")
        XCTAssertEqual(lingora.translate("hello", table: "app", bundle: second), "Second")
        MockURLProtocol.responses = [.init(status: 200, headers: [:], data: Data(#"{"hello":"Remote"}"#.utf8))]
        await lingora.remoteFetch()
        XCTAssertEqual(lingora.translate("hello", table: "app", bundle: first), "Remote")
        XCTAssertEqual(lingora.translate("local", table: "app", bundle: first), "Local")
        try lingora.clearCache()
        XCTAssertEqual(lingora.translate("hello", table: "app", bundle: first), "First")
    }

    /// 默认关闭；无效 JSON、超限文件和不安全路径不能破坏原生回退。
    func testBundledJSONOptInAndInvalidResources() throws {
        let bundle = try makeJSONBundle([
            "Lingora/app/en-US.json": #"{"hello":{"variations":{"plural":{"one":"bad"}}}}"#,
            "Lingora/app/en.json": #"{"hello":"JSON"}"#,
            "Lingora/large/en.json": String(repeating: " ", count: TranslationDocument.maximumBytes + 1),
            "en.lproj/app.strings": #""hello" = "Native";"#,
        ])
        let disabled = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("off"))
        disabled.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, locale: Locale(identifier: "en-US"))
        XCTAssertEqual(disabled.translate("hello", table: "app", bundle: bundle), "Native")
        let enabled = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("on"))
        enabled.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!,
                           locale: Locale(identifier: "en-US"), bundledTranslationsDirectory: "Lingora")
        XCTAssertEqual(enabled.translate("hello", table: "app", bundle: bundle), "JSON")
        XCTAssertEqual(enabled.translate("hello", table: "large", bundle: bundle), "hello")
        let store = BundledTranslationStore()
        XCTAssertNil(store.template(for: "hello", bundle: bundle, directory: "Lingora",
                                    language: "en", table: "../Lingora/app", locale: Locale(identifier: "en"), arguments: []))
        let invalid = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("invalid"))
        invalid.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, bundledTranslationsDirectory: "../Lingora")
        XCTAssertFalse(invalid.isInitialized)
    }

    /// 新版 JSON 语言无需在 main Bundle 的 lproj 中注册，framework 可直接按 locale 切换。
    func testJSONOnlyLocaleWithoutExplicitLanguage() throws {
        let bundle = try makeJSONBundle(["Lingora/common/ja.json": #"{"hello":"日本語"}"#])
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, bundledTranslationsDirectory: "Lingora")
        try sdk.setCustomLocale(Locale(identifier: "ja"))
        XCTAssertEqual(sdk.translate("hello", table: "common", bundle: bundle), "日本語")
        XCTAssertThrowsError(try sdk.setCustomLocale(Locale(identifier: "../escape")))
    }

    /// 错误远端参数回退到 JSON，错误 JSON 参数继续回退原生资源。
    func testUnsafeTemplatesFallBackWithoutFormatting() async throws {
        let bundle = try makeJSONBundle([
            "Lingora/app/en.json": #"{"hello":"Bundle %@","native":"%lld"}"#,
            "en.lproj/app.strings": #""native" = "Native %@";"#,
        ])
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!,
                       locale: Locale(identifier: "en"), language: "en", namespaces: ["app"],
                       bundledTranslationsDirectory: "Lingora")
        MockURLProtocol.responses = [.init(status: 200, headers: [:], data: Data(#"{"hello":"%n","native":"%@ %@"}"#.utf8))]
        await sdk.remoteFetch()
        XCTAssertEqual(sdk.translate("hello", "iOS", table: "app", bundle: bundle), "Bundle iOS")
        XCTAssertEqual(sdk.translate("native", "iOS", table: "app", bundle: bundle), "Native iOS")
    }

    /// 同一 URL 的并发刷新按顺序写盘，旧请求不再覆盖最新请求的内存状态。
    func testConcurrentRefreshKeepsLatestMemoryAndCache() async throws {
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"hello":"old"}"#.utf8), delay: 0.2),
            .init(status: 200, headers: [:], data: Data(#"{"hello":"new"}"#.utf8)),
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let first = Task { await sdk.remoteFetch() }
        let started = await waitUntil { MockURLProtocol.requestCount == 1 }
        XCTAssertTrue(started)
        let second = Task { await sdk.remoteFetch() }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(MockURLProtocol.requestCount, 1, "Same URL must not fetch concurrently")
        await first.value
        await second.value
        XCTAssertEqual(sdk.translate("hello"), "new")
        XCTAssertEqual(sdk.loadState, .loaded(source: .network, failedTables: []))
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        let restored = Lingora(session: makeSession(), cacheDirectory: temporary)
        restored.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let ready = await waitUntil { restored.lastFetchSource == .cache }
        XCTAssertTrue(ready)
        XCTAssertEqual(restored.translate("hello"), "new")
    }

    /// 加载状态发送初始值，冷却不重复请求，显式刷新可立即重试且成功后清除冷却。
    func testLoadStatesAndFailureCooldown() async throws {
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        var states = sdk.onLoadStateChanged().makeAsyncIterator()
        let initial = await states.next()
        XCTAssertEqual(initial, .idle)
        MockURLProtocol.responses = [.init(status: 404, headers: [:], data: Data())]
        await sdk.remoteFetch(forceRefresh: false)
        let loading = await states.next()
        let failed = await states.next()
        XCTAssertEqual(loading, .loading)
        XCTAssertEqual(failed, .fallback(failedTables: [""]))
        await sdk.remoteFetch(forceRefresh: false)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        MockURLProtocol.responses = [.init(status: 200, headers: [:], data: Data(#"{"hello":"recovered"}"#.utf8))]
        await sdk.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertEqual(sdk.translate("hello"), "recovered")
        XCTAssertEqual(sdk.loadState, .loaded(source: .network, failedTables: []))
        try sdk.clearCache()
        XCTAssertEqual(sdk.loadState, .idle)
    }

    /// 冷却到期后恢复请求；同一 namespace 的失败不阻塞另一个 namespace。
    func testCooldownExpiryAndNamespaceIsolation() async throws {
        let store = ContentDeliveryStore(cacheDirectory: temporary, session: makeSession(), appVersion: "1", failureCooldown: .milliseconds(20))
        let base = URL(string: "https://cdn.example.com")!
        MockURLProtocol.responses = [.init(status: 404, headers: [:], data: Data()),
            .init(status: 200, headers: [:], data: Data(#"{"hello":"common"}"#.utf8)),
            .init(status: 200, headers: [:], data: Data(#"{"hello":"app"}"#.utf8))]
        _ = await store.load(baseURL: base, language: "en", table: "app", forceRefresh: false)
        let common = await store.load(baseURL: base, language: "en", table: "common", forceRefresh: false)
        XCTAssertEqual(common.source, .network)
        try await Task.sleep(for: .milliseconds(30))
        let app = await store.load(baseURL: base, language: "en", table: "app", forceRefresh: false)
        XCTAssertEqual(app.source, .network)
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
    }

    /// 取消排队中的刷新不会再发请求，也不能将旧请求结果应用为新请求成功。
    func testCancelledQueuedRefreshDoesNotFetch() async throws {
        MockURLProtocol.responses = [.init(status: 200, headers: [:], data: Data(#"{"hello":"old"}"#.utf8), delay: 0.2)]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let first = Task { await sdk.remoteFetch() }
        let started = await waitUntil { MockURLProtocol.requestCount == 1 }
        XCTAssertTrue(started)
        let queued = Task { await sdk.remoteFetch() }
        try await Task.sleep(for: .milliseconds(10))
        queued.cancel()
        await first.value
        await queued.value
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertEqual(sdk.loadState, .cancelled)
    }

    /// 失败冷却只缓存截止时间，清理磁盘后不能从冷却结果复活旧文档。
    func testCooldownDoesNotRetainClearedCache() async throws {
        let store = ContentDeliveryStore(cacheDirectory: temporary, session: makeSession(), appVersion: "1")
        let base = URL(string: "https://cdn.example.com")!
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"hello":"old"}"#.utf8)),
            .init(status: 404, headers: [:], data: Data()),
        ]
        _ = await store.load(baseURL: base, language: "en", table: "app")
        let failure = await store.load(baseURL: base, language: "en", table: "app", forceRefresh: false)
        XCTAssertEqual(failure.source, .cache)
        try store.clear()
        let cooling = await store.load(baseURL: base, language: "en", table: "app", forceRefresh: false)
        XCTAssertNil(cooling.document)
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    /// 默认不启用全局 Bundle swizzling。
    func testSwizzlingIsOptIn() {
        XCTAssertFalse(BundleSwizzler.isEnabled)
        let lingora = Lingora(
            session: makeSession(),
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en",
            enableSwizzling: false
        )
        XCTAssertFalse(BundleSwizzler.isEnabled)
    }

    /// 重复 initialize 必须保留第一次 URL、语言和 namespace 配置。
    func testRepeatedInitializeIsIgnored() async {
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"first"}"#.utf8))
        ]
        let lingora = Lingora(
            session: makeSession(),
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://first.example.com/base")!,
            language: "en",
            namespaces: ["app"],
            enableDebugLogs: true
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://second.example.com")!,
            language: "ja",
            namespaces: ["common"]
        )

        await lingora.remoteFetch()

        XCTAssertEqual(MockURLProtocol.requests.first?.url?.host, "first.example.com")
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, "/base/app/en.json")
        XCTAssertEqual(lingora.translate("welcome", table: "app"), "first")
    }

    /// 根文档和具名 namespace 使用不同 URL；一个 namespace 失败不清空另一个。
    func testRootPathAndPartialNamespaceFailure() async {
        let root = Lingora(
            session: makeSession(),
            cacheDirectory: temporary.appendingPathComponent("root"),
            appVersion: "1"
        )
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"root"}"#.utf8))
        ]
        root.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com/base")!,
            language: "en"
        )
        await root.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, "/base/en.json")

        MockURLProtocol.requests = []
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [
                .init(
                    status: 200,
                    headers: [:],
                    data: Data(#"{"shared":"app value"}"#.utf8)
                )
            ],
            "/common/en.json": [
                .init(status: 503, headers: [:], data: Data()),
                .init(status: 503, headers: [:], data: Data()),
            ],
        ]
        let namespaced = Lingora(
            session: makeSession(),
            cacheDirectory: temporary.appendingPathComponent("namespaced"),
            appVersion: "1"
        )
        namespaced.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en",
            namespaces: ["app", "common"]
        )
        await namespaced.remoteFetch()

        XCTAssertEqual(namespaced.translate("shared", table: "app"), "app value")
        XCTAssertEqual(namespaced.translate("shared", table: "common"), "shared")
        XCTAssertEqual(namespaced.lastFetchSource, .network)
        XCTAssertEqual(namespaced.loadState, .loaded(source: .network, failedTables: ["common"]))
        XCTAssertEqual(MockURLProtocol.requests.filter { $0.url?.path == "/common/en.json" }.count, 2)
    }

    /// 304 但缓存损坏时必须清除条件并无条件恢复一次。
    func testNotModifiedWithCorruptCacheRetriesUnconditionally() async throws {
        let session = makeSession()
        let online = Lingora(session: session, cacheDirectory: temporary, appVersion: "1")
        MockURLProtocol.responses = [
            .init(
                status: 200,
                headers: ["ETag": "v1"],
                data: Data(#"{"welcome":"old"}"#.utf8)
            )
        ]
        online.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        await online.remoteFetch()
        let cacheFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: temporary,
                includingPropertiesForKeys: nil
            ).first(where: { $0.pathExtension == "json" })
        )
        try Data("broken".utf8).write(to: cacheFile)

        MockURLProtocol.requests = []
        MockURLProtocol.responses = [
            .init(status: 304, headers: [:], data: Data()),
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"new"}"#.utf8)),
        ]
        let recovered = Lingora(session: session, cacheDirectory: temporary, appVersion: "1")
        recovered.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        await recovered.remoteFetch()

        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertNil(MockURLProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(recovered.translate("welcome"), "new")
    }

    /// 初始化应异步恢复缓存，不要求调用方先发起网络刷新。
    func testInitializeRestoresDiskCacheAsynchronously() async {
        let session = makeSession()
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"cached"}"#.utf8))
        ]
        let online = Lingora(session: session, cacheDirectory: temporary, appVersion: "1")
        online.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        await online.remoteFetch()
        MockURLProtocol.requests = []

        let restored = Lingora(session: session, cacheDirectory: temporary, appVersion: "1")
        restored.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )

        let didRestore = await waitUntil { restored.lastFetchSource == .cache }
        XCTAssertTrue(didRestore)
        XCTAssertEqual(restored.translate("welcome"), "cached")
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    /// 初始化缓存恢复与网络刷新并发时，旧缓存不得覆盖较新的网络文档和来源状态。
    func testNetworkRefreshWinsOverConcurrentCacheRestore() async {
        let session = makeSession()
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"cached"}"#.utf8))
        ]
        let cached = Lingora(session: session, cacheDirectory: temporary, appVersion: "1")
        cached.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        await cached.remoteFetch()

        MockURLProtocol.requests = []
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"network"}"#.utf8))
        ]
        let refreshed = Lingora(session: session, cacheDirectory: temporary, appVersion: "1")
        refreshed.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        await refreshed.remoteFetch()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(refreshed.translate("welcome"), "network")
        XCTAssertEqual(refreshed.lastFetchSource, .network)
    }

    /// 语言切换后的旧 generation 请求完成时不得污染新语言内存状态。
    func testStaleGenerationIsNotApplied() async throws {
        MockURLProtocol.responses = [
            .init(
                status: 200,
                headers: [:],
                data: Data(#"{"welcome":"stale"}"#.utf8),
                delay: 0.15
            )
        ]
        let lingora = Lingora(
            session: makeSession(),
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        let fetch = Task { await lingora.remoteFetch() }
        try await Task.sleep(for: .milliseconds(20))
        try lingora.setCustomLocale(Locale(identifier: "ja"), language: "ja")
        await fetch.value

        XCTAssertEqual(lingora.translate("welcome"), "welcome")
        XCTAssertNil(lingora.lastFetchDate)
    }

    /// 超限响应不能进入内存或磁盘缓存。
    func testOversizedResponseIsRejected() async {
        MockURLProtocol.responses = [
            .init(
                status: 200,
                headers: [:],
                data: Data(repeating: 0, count: TranslationDocument.maximumBytes + 1)
            )
        ]
        let lingora = Lingora(
            session: makeSession(),
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )

        await lingora.remoteFetch()

        XCTAssertEqual(lingora.translate("welcome"), "welcome")
        XCTAssertNil(lingora.lastFetchDate)
    }

    /// 应用有效文档时必须发送公开更新流事件。
    func testTranslationsUpdatedStreamEmitsAfterFetch() async {
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"updated"}"#.utf8))
        ]
        let lingora = Lingora(
            session: makeSession(),
            cacheDirectory: temporary,
            appVersion: "1"
        )
        lingora.initialize(
            contentDeliveryURL: URL(string: "https://cdn.example.com")!,
            language: "en"
        )
        let updated = expectation(description: "translations updated")
        let observer = Task {
            for await _ in lingora.onTranslationsUpdated() {
                updated.fulfill()
                return
            }
        }

        await lingora.remoteFetch()
        await fulfillment(of: [updated], timeout: 1)
        observer.cancel()
    }

    /// 创建只使用 MockURLProtocol 的会话。
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// 在限定时间内等待 MainActor 状态变化。
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

}
