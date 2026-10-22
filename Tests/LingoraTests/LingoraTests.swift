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
        if item.delay > 0 { Thread.sleep(forTimeInterval: item.delay) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: item.status,
            httpVersion: "HTTP/1.1",
            headerFields: item.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: item.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// 测试响应无需取消额外工作。
    override func stopLoading() {}
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
