// 验证 Lingora 公开 API 的网络、缓存、格式化和失败回退。
import Foundation
import XCTest
import Combine
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
        await sdk.preload()
        let loading = await states.next()
        let failed = await states.next()
        XCTAssertEqual(loading, .loading)
        XCTAssertEqual(failed, .fallback(failedTables: [""]))
        await sdk.preload()
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

    /// 取消排队刷新立即退出，不发请求也不覆盖正在执行的刷新状态。
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
        await queued.value
        XCTAssertEqual(sdk.loadState, .loading)
        await first.value
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        XCTAssertEqual(sdk.loadState, .loaded(source: .network, failedTables: []))
        XCTAssertEqual(sdk.translate("hello"), "old")
    }

    /// 切换语言后，旧语言的排队请求不再联网或覆盖新语言状态。
    func testLocaleSwitchInvalidatesQueuedRefresh() async throws {
        MockURLProtocol.responsesByPath = [
            "/en.json": [.init(status: 200, headers: [:], data: Data(#"{"hello":"old"}"#.utf8), delay: 0.2)],
            "/ja.json": [.init(status: 200, headers: [:], data: Data(#"{"hello":"new"}"#.utf8))]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let first = Task { await sdk.remoteFetch() }
        let started = await waitUntil { MockURLProtocol.requestCount == 1 }
        XCTAssertTrue(started)
        let queued = Task { await sdk.remoteFetch() }
        try await Task.sleep(for: .milliseconds(10))
        try sdk.setCustomLocale(Locale(identifier: "ja"), language: "ja")
        await sdk.preload()
        await first.value
        await queued.value
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
        XCTAssertEqual(sdk.translate("hello"), "new")
        XCTAssertEqual(sdk.loadState, .loaded(source: .network, failedTables: []))
    }

    /// 清理磁盘同时使失败冷却失效；下一次 preload 重新请求且不复活旧文档。
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
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
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

    /// 默认 namespace 仅影响 SDK 文档；显式 table 和原生 Localizable 仍各自独立。
    func testDefaultNamespaceAndNativeFallback() async throws {
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"app"}"#.utf8))],
            "/common/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"common"}"#.utf8))]
        ]
        let resources = temporary.appendingPathComponent("Native.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data(#""native" = "native fallback";"#.utf8).write(to: resources.appendingPathComponent("Localizable.strings"))
        let lingora = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("cache"))
        lingora.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en",
                           namespaces: ["common"], defaultNamespace: "app")
        await lingora.remoteFetch()
        XCTAssertEqual(lingora.translate("welcome"), "app")
        XCTAssertEqual(lingora.translate("welcome", table: "common"), "common")
        XCTAssertEqual(lingora.translate("native", bundle: Bundle(url: resources)!), "native fallback")
        XCTAssertEqual(Set(MockURLProtocol.requests.compactMap { $0.url?.path }), ["/app/en.json", "/common/en.json"])
    }

    /// 语言匹配后的 plural 使用实际文档语言，显式 language 保持精确请求。
    func testMatchedLanguageAndExplicitOverride() async throws {
        MockURLProtocol.responsesByPath = [
            "/en.json": [.init(status: 200, headers: [:], data: Data(#"{"items":{"variations":{"plural":{"one":"one","other":"other"}}}}"#.utf8))],
            "/ja-JP.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"explicit"}"#.utf8))]
        ]
        let lingora = Lingora(session: makeSession(), cacheDirectory: temporary)
        lingora.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, locale: Locale(identifier: "ja-JP"),
                           availableLanguages: ["en"], defaultLanguage: "en")
        await lingora.remoteFetch()
        XCTAssertEqual(lingora.resolvedLanguage, "en")
        XCTAssertEqual(lingora.translate("items", 1), "one")
        try lingora.setCustomLocale(Locale(identifier: "ja-JP"), language: "ja-JP")
        await lingora.remoteFetch()
        XCTAssertEqual(lingora.resolvedLanguage, "ja-JP")
        XCTAssertEqual(lingora.translate("welcome"), "explicit")
    }

    /// SDK 默认 namespace 同样适用于离线 JSON，显式根 table 不被替换。
    func testDefaultNamespaceBundledJSON() throws {
        let bundle = try makeJSONBundle([
            "Lingora/app/en.json": #"{"welcome":"App offline"}"#,
            "Lingora/en.json": #"{"welcome":"Root offline"}"#
        ])
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary.appendingPathComponent("cache"))
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en",
                       bundledTranslationsDirectory: "Lingora", defaultNamespace: "app")
        XCTAssertEqual(sdk.translate("welcome", bundle: bundle), "App offline")
        XCTAssertEqual(sdk.translate("welcome", table: "", bundle: bundle), "Root offline")
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }

    /// 与 Android 相同：初始化不请求网络，preload 合并消费者请求，refresh 始终检查远端。
    func testPreloadCoalescesAndRefreshesExplicitly() async throws {
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"first"}"#.utf8), delay: 0.05),
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"refreshed"}"#.utf8))
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
        let first = Task { await sdk.preload() }
        let second = Task { await sdk.preload() }
        await first.value
        await second.value
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertEqual(sdk.translate("welcome"), "first")
        await sdk.remoteFetch()
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
        XCTAssertEqual(sdk.translate("welcome"), "refreshed")
    }

    /// SwiftUI 的订阅与 Android tFlow 一样按需加载，切换后旧请求不能覆盖当前语言。
    func testSwiftUIConsumerLoadsAndSwitches() async throws {
        MockURLProtocol.responsesByPath = [
            "/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"old"}"#.utf8), delay: 0.2)],
            "/ja.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"new"}"#.utf8))]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let updater = LingoraSwiftUIUpdater(lingora: sdk)
        let started = await waitUntil { MockURLProtocol.requestCount == 1 }
        XCTAssertTrue(started)
        try sdk.setCustomLocale(Locale(identifier: "ja"))
        let loaded = await waitUntil { sdk.translate("welcome") == "new" }
        XCTAssertTrue(loaded)
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
        XCTAssertEqual(sdk.resolvedLanguage, "ja")
        withExtendedLifetime(updater) {}
    }

    /// 已恢复缓存立即可读，但首次 preload 仍检查网络以免永远停留在旧翻译。
    func testPreloadRefreshesRestoredCache() async throws {
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"cached"}"#.utf8)),
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"fresh"}"#.utf8))
        ]
        let initial = Lingora(session: makeSession(), cacheDirectory: temporary)
        initial.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        await initial.remoteFetch()
        let restored = Lingora(session: makeSession(), cacheDirectory: temporary)
        restored.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let cached = await waitUntil { restored.translate("welcome") == "cached" }
        XCTAssertTrue(cached)
        await restored.preload()
        XCTAssertEqual(restored.translate("welcome"), "fresh")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    /// 无匹配且无默认语言时只回退 Bundle，不猜测其他地区或发出无效请求。
    func testLanguageConfigurationAndNoMatch() async throws {
        let base = URL(string: "https://cdn.example.com")!
        for languages in [["en", "EN"], ["../en"]] {
            let invalid = Lingora(session: makeSession(), cacheDirectory: temporary)
            invalid.initialize(contentDeliveryURL: base, availableLanguages: languages)
            XCTAssertFalse(invalid.isInitialized)
        }
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: base, locale: Locale(identifier: "en-AU"), availableLanguages: ["en-US"])
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
        XCTAssertEqual(sdk.loadState, .fallback(failedTables: [""]))
    }

    /// 部分 namespace 失败时预加载不重下成功文档，失败 namespace 遵守同一冷却门禁。
    func testPreloadRetainsSuccessfulNamespacesDuringCooldown() async {
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"app"}"#.utf8))],
            "/common/en.json": [.init(status: 404, headers: [:], data: Data())]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en",
                       namespaces: ["common"], defaultNamespace: "app")
        await sdk.preload()
        await sdk.preload()
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
        XCTAssertEqual(sdk.translate("welcome"), "app")
        XCTAssertEqual(sdk.loadState, .loaded(source: .network, failedTables: ["common"]))
    }

    /// 缺失 namespace 的局部预加载不能丢弃并发完整刷新的有效结果。
    func testPartialPreloadDoesNotDiscardFullRefresh() async throws {
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"v1"}"#.utf8))],
            "/common/en.json": [.init(status: 404, headers: [:], data: Data())]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en", namespaces: ["common"], defaultNamespace: "app")
        await sdk.preload()
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"v2"}"#.utf8), delay: 0.3)],
            "/common/en.json": [.init(status: 404, headers: [:], data: Data())]
        ]
        let refresh = Task { await sdk.remoteFetch() }
        let started = await waitUntil { MockURLProtocol.requestCount == 4 }
        XCTAssertTrue(started)
        try await Task.sleep(for: .milliseconds(30))
        await sdk.preload()
        await refresh.value
        XCTAssertEqual(sdk.translate("welcome"), "v2")
    }

    /// 网络尚未返回时，恢复的磁盘缓存必须立即通知 SwiftUI。
    func testSwiftUICacheNotificationDoesNotWaitForNetwork() async throws {
        MockURLProtocol.responses = [
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"cached"}"#.utf8)),
            .init(status: 200, headers: [:], data: Data(#"{"welcome":"fresh"}"#.utf8), delay: 0.4)
        ]
        let initial = Lingora(session: makeSession(), cacheDirectory: temporary)
        initial.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        await initial.remoteFetch()
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let updater = LingoraSwiftUIUpdater(lingora: sdk)
        var notifications = 0
        let subscription = updater.objectWillChange.sink { _ in notifications += 1 }
        let cached = await waitUntil { sdk.translate("welcome") == "cached" }
        XCTAssertTrue(cached)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertGreaterThan(notifications, 0)
        let completed = await waitUntil { sdk.translate("welcome") == "fresh" }
        XCTAssertTrue(completed)
        withExtendedLifetime(subscription) {}
        withExtendedLifetime(updater) {}
    }

    /// 清理发生在手动刷新期间时，旧请求不得复活磁盘或内存缓存。
    func testClearDuringManualRefreshDoesNotRepopulateCache() async throws {
        MockURLProtocol.responses = [.init(status: 200, headers: [:], data: Data(#"{"welcome":"obsolete"}"#.utf8), delay: 0.2)]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary, appVersion: "1")
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        let fetch = Task { await sdk.remoteFetch() }
        let started = await waitUntil { MockURLProtocol.requestCount == 1 }
        XCTAssertTrue(started)
        let queued = Task { await sdk.remoteFetch() }
        try await Task.sleep(for: .milliseconds(10))
        try sdk.clearCache()
        await fetch.value
        await queued.value
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertEqual(sdk.loadState, .idle)
        XCTAssertEqual(sdk.translate("welcome"), "welcome")
        let store = ContentDeliveryStore(cacheDirectory: temporary, session: makeSession(), appVersion: "1")
        let cached = await store.cached(baseURL: URL(string: "https://cdn.example.com")!, language: "en", table: "")
        XCTAssertNil(cached, "A request invalidated by clearCache must not restore the cleared disk cache")
    }

    /// 自动匹配与显式语言交替加载时，每种语言独立保留 namespace 和已加载标记。
    func testExplicitLanguageDoesNotPoisonMissingNamespaceTracking() async throws {
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"app-base"}"#.utf8))],
            "/common/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"common-base"}"#.utf8))],
            "/app/en-US.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"app-exact"}"#.utf8))],
            "/common/en-US.json": [.init(status: 404, headers: [:], data: Data())]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, locale: Locale(identifier: "en-US"), namespaces: ["app", "common"], availableLanguages: ["en"])
        await sdk.preload()
        XCTAssertEqual(sdk.translate("welcome", table: "common"), "common-base")
        await sdk.remoteFetch(language: "en-US")
        XCTAssertEqual(sdk.translate("welcome", table: "app"), "app-exact")
        XCTAssertEqual(sdk.translate("welcome", table: "common"), "welcome")
        await sdk.preload()
        XCTAssertEqual(sdk.translate("welcome", table: "app"), "app-base")
        XCTAssertEqual(MockURLProtocol.requestCount, 4)
        XCTAssertEqual(sdk.translate("welcome", table: "common"), "common-base", "A table discarded with a different resolved language must not remain marked loaded")
    }

    /// 切回已加载语言直接复用内存，namespace 不跨语言混用；清理后必须重新加载。
    func testLocaleSwitchReusesLanguageNamespaceDocuments() async throws {
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"app-en"}"#.utf8))],
            "/common/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"common-en"}"#.utf8))],
            "/app/ja.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"app-ja"}"#.utf8))],
            "/common/ja.json": [.init(status: 404, headers: [:], data: Data())]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en", namespaces: ["app", "common"])
        await sdk.preload()
        try sdk.setCustomLocale(Locale(identifier: "ja"), language: "ja")
        await sdk.preload()
        XCTAssertEqual(sdk.translate("welcome", table: "app"), "app-ja")
        XCTAssertEqual(sdk.translate("welcome", table: "common"), "welcome")
        try sdk.setCustomLocale(Locale(identifier: "en"), language: "en")
        XCTAssertEqual(sdk.translate("welcome", table: "common"), "common-en")
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 4)
        try sdk.clearCache()
        XCTAssertEqual(sdk.translate("welcome", table: "common"), "welcome")
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 6)
    }

    /// 清理使在途、排队及尚未启动的旧代次请求全部失效，覆盖 200、304 和失败回退。
    func testClearInvalidatesInFlightQueuedAndDeferredCacheLoads() async throws {
        let base = URL(string: "https://cdn.example.com")!
        for status in [200, 304, 404] {
            let store = ContentDeliveryStore(cacheDirectory: temporary.appendingPathComponent(String(status)), session: makeSession(), appVersion: "1")
            MockURLProtocol.responses = [
                .init(status: 200, headers: ["ETag": "old"], data: Data(#"{"welcome":"cached"}"#.utf8)),
                .init(status: status, headers: [:], data: Data(#"{"welcome":"obsolete"}"#.utf8), delay: 0.15)
            ]
            _ = await store.load(baseURL: base, language: "en", table: "")
            let generation = store.cacheGeneration
            let count = MockURLProtocol.requestCount
            let first = Task { await store.load(baseURL: base, language: "en", table: "") }
            let started = await waitUntil { MockURLProtocol.requestCount == count + 1 }
            XCTAssertTrue(started)
            let queued = Task { await store.load(baseURL: base, language: "en", table: "", cacheGeneration: generation) }
            try await Task.sleep(for: .milliseconds(10))
            try store.clear()
            let result = await first.value
            let queuedResult = await queued.value
            XCTAssertTrue(result.isCancelled)
            XCTAssertNil(result.document)
            XCTAssertTrue(queuedResult.isCancelled)
            let cached = await store.cached(baseURL: base, language: "en", table: "")
            XCTAssertNil(cached)
            let deferred = await store.load(baseURL: base, language: "en", table: "", cacheGeneration: generation)
            XCTAssertTrue(deferred.isCancelled)
            XCTAssertEqual(MockURLProtocol.requestCount, count + 1)
            MockURLProtocol.responses = [.init(status: 200, headers: [:], data: Data(#"{"welcome":"fresh"}"#.utf8))]
            let fresh = await store.load(baseURL: base, language: "en", table: "", forceRefresh: false)
            XCTAssertEqual(fresh.source, .network)
            XCTAssertNil(MockURLProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match"))
            let saved = await store.cached(baseURL: base, language: "en", table: "")
            XCTAssertEqual(saved?.document?.values["welcome"], .text("fresh"))
        }
    }

    /// 显式请求的文档语言全部失败时，仍显示最后有效的匹配语言文档。
    func testFailedExactRefreshRetainsMatchedDocuments() async {
        MockURLProtocol.responsesByPath = [
            "/app/en.json": [.init(status: 200, headers: [:], data: Data(#"{"welcome":"matched"}"#.utf8))],
            "/app/en-US.json": [.init(status: 404, headers: [:], data: Data())]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, locale: Locale(identifier: "en-US"), defaultNamespace: "app", availableLanguages: ["en"])
        await sdk.preload()
        await sdk.remoteFetch(language: "en-US")
        XCTAssertEqual(sdk.translate("welcome"), "matched")
        XCTAssertEqual(sdk.resolvedLanguage, "en")
        XCTAssertEqual(sdk.loadState, .fallback(failedTables: ["app"]))
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    /// 切走时完成的手动刷新更新原语言缓存，切回时不能因已加载标记而永久停留在旧值。
    func testRefreshCompletingAfterLocaleSwitchUpdatesOnlyItsLanguage() async throws {
        MockURLProtocol.responsesByPath = [
            "/en.json": [
                .init(status: 200, headers: [:], data: Data(#"{"welcome":"old"}"#.utf8)),
                .init(status: 200, headers: [:], data: Data(#"{"welcome":"fresh"}"#.utf8), delay: 0.15)
            ]
        ]
        let sdk = Lingora(session: makeSession(), cacheDirectory: temporary)
        sdk.initialize(contentDeliveryURL: URL(string: "https://cdn.example.com")!, language: "en")
        await sdk.preload()
        let refresh = Task { await sdk.remoteFetch() }
        let started = await waitUntil { MockURLProtocol.requestCount == 2 }
        XCTAssertTrue(started)
        try sdk.setCustomLocale(Locale(identifier: "ja"), language: "ja")
        await refresh.value
        XCTAssertEqual(sdk.translate("welcome"), "welcome")
        XCTAssertEqual(sdk.loadState, .idle)
        try sdk.setCustomLocale(Locale(identifier: "en"), language: "en")
        XCTAssertEqual(sdk.translate("welcome"), "fresh")
        await sdk.preload()
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
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
