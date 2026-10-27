// 下载 Content Delivery 文档并按 App 版本、语言和 namespace 原子缓存。
import Foundation

/// 保存一次加载结果及非致命警告。
struct LoadedDocument: Sendable {
    let document: TranslationDocument?
    let source: LingoraFetchSource?
    let warning: String?
    let isCancelled: Bool
}

/// 序列化有效文档和 HTTP 校验器。
private struct CacheEntry: Codable {
    let data: Data
    let etag: String?
    let lastModified: String?
}

/// 同步清理 API 与异步请求共享的缓存屏障；锁只覆盖代次及磁盘操作，不覆盖网络等待。
private final class CacheBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: UInt64 = 0

    /// 读取请求所属代次。
    var generation: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    /// 只允许当前代次读取或提交缓存，与 clear 使用同一把锁。
    func perform<T>(generation: UInt64, _ operation: () throws -> T) rethrows -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == generation else { return nil }
        return try operation()
    }

    /// 先使所有旧请求失效，再删除磁盘；删除失败也不能让旧请求继续写入。
    func clear(directory: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        epoch &+= 1
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// 隔离 Content Delivery 的磁盘与网络 I/O。
actor ContentDeliveryStore {
    private let cacheDirectory: URL
    private let session: URLSession
    private let appVersion: String
    private let failureCooldown: Duration
    private var waiters: [URL: [CheckedContinuation<Void, Never>]] = [:]
    private var failures: [URL: ContinuousClock.Instant] = [:]
    private var failureGeneration: UInt64 = 0
    private nonisolated let cacheBarrier = CacheBarrier()

    /// 在生成网络子任务前捕获代次，防止清理前创建的任务延迟启动后写回缓存。
    nonisolated var cacheGeneration: UInt64 { cacheBarrier.generation }

    /// 注入网络会话和缓存目录，便于隔离测试。
    init(cacheDirectory: URL, session: URLSession, appVersion: String, failureCooldown: Duration = .seconds(5)) {
        self.cacheDirectory = cacheDirectory
        self.session = session
        self.appVersion = appVersion
        self.failureCooldown = failureCooldown
    }

    /// 加载一个 language/table，网络失败时保留最后有效缓存。
    func load(baseURL: URL, language: String, table: String, forceRefresh: Bool = true, cacheGeneration: UInt64? = nil) async -> LoadedDocument {
        let generation = cacheGeneration ?? self.cacheGeneration
        let url = Self.documentURL(baseURL: baseURL, language: language, table: table)
        await acquire(url)
        defer { release(url) }
        guard !Task.isCancelled, generation == self.cacheGeneration else {
            return LoadedDocument(document: nil, source: nil, warning: nil, isCancelled: true)
        }
        if failureGeneration != generation {
            failures = [:]
            failureGeneration = generation
        }
        if !forceRefresh, let deadline = failures[url], ContinuousClock.now < deadline {
            let document = cacheBarrier.perform(generation: generation) { Self.readCache(at: cacheFile(for: url)).document } ?? nil
            return LoadedDocument(document: document, source: document == nil ? nil : .cache,
                                  warning: "Translation fetch is cooling down after failure", isCancelled: false)
        }
        let result = await Self.fetch(url: url, cacheFile: cacheFile(for: url), session: session, barrier: cacheBarrier, generation: generation)
        guard generation == self.cacheGeneration else {
            return LoadedDocument(document: nil, source: nil, warning: nil, isCancelled: true)
        }
        if !result.isCancelled && result.warning != nil && result.source != .network {
            failures[url] = ContinuousClock.now.advanced(by: failureCooldown)
        } else if !result.isCancelled {
            failures[url] = nil
        }
        return result
    }

    /// 同一 URL 顺序执行请求与缓存写入，不同 namespace 保持并行。
    private func acquire(_ url: URL) async {
        if waiters[url] == nil {
            waiters[url] = []
        } else {
            await withCheckedContinuation { waiters[url, default: []].append($0) }
        }
    }

    /// 将请求执行权移交给下一个等待者，取消者在获得执行权后直接退出。
    private func release(_ url: URL) {
        guard var queue = waiters[url], !queue.isEmpty else {
            waiters[url] = nil
            return
        }
        let continuation = queue.removeFirst()
        waiters[url] = queue
        continuation.resume()
    }

    /// 只读取一个 language/table 的有效磁盘缓存，不发起网络请求。
    func cached(baseURL: URL, language: String, table: String) -> LoadedDocument? {
        let url = Self.documentURL(baseURL: baseURL, language: language, table: table)
        guard let document = cacheBarrier.perform(generation: cacheGeneration, { Self.readCache(at: cacheFile(for: url)).document }) ?? nil else {
            return nil
        }
        return LoadedDocument(
            document: document,
            source: .cache,
            warning: nil,
            isCancelled: false
        )
    }

    /// 删除当前 SDK 的全部磁盘缓存。
    nonisolated func clear() throws {
        try cacheBarrier.clear(directory: cacheDirectory)
    }

    /// 生成默认 table 或 namespace table 的公开 URL。
    static func documentURL(baseURL: URL, language: String, table: String) -> URL {
        let root = table.isEmpty ? baseURL : baseURL.appendingPathComponent(table)
        return root.appendingPathComponent(language).appendingPathExtension("json")
    }

    /// 按 URL、App 版本、语言和 table 生成隔离缓存路径。
    private func cacheFile(for url: URL) -> URL {
        let key = "\(url.absoluteString)|\(appVersion)"
        return cacheDirectory
            .appendingPathComponent(Self.stableHash(key), isDirectory: false)
            .appendingPathExtension("json")
    }

    /// 执行条件请求；任何无效响应都不覆盖缓存。
    private static func fetch(
        url: URL,
        cacheFile: URL,
        session: URLSession,
        barrier: CacheBarrier,
        generation: UInt64
    ) async -> LoadedDocument {
        guard let cached = barrier.perform(generation: generation, { readCache(at: cacheFile) }) else {
            return LoadedDocument(document: nil, source: nil, warning: nil, isCancelled: true)
        }
        var conditional = true
        requestLoop: for attempt in 0...1 {
            if Task.isCancelled || barrier.generation != generation {
                return LoadedDocument(
                    document: nil,
                    source: nil,
                    warning: nil,
                    isCancelled: true
                )
            }
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 15
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if conditional, let entry = cached.entry, cached.document != nil {
                request.setValue(entry.etag, forHTTPHeaderField: "If-None-Match")
                request.setValue(
                    entry.lastModified,
                    forHTTPHeaderField: "If-Modified-Since"
                )
            }
            do {
                let (data, response) = try await session.data(for: request)
                if Task.isCancelled || barrier.generation != generation {
                    return LoadedDocument(
                        document: nil,
                        source: nil,
                        warning: nil,
                        isCancelled: true
                    )
                }
                guard let http = response as? HTTPURLResponse else {
                    break requestLoop
                }
                if http.statusCode == 304 {
                    if let document = cached.document {
                        return LoadedDocument(
                            document: document,
                            source: .cache,
                            warning: nil,
                            isCancelled: false
                        )
                    }
                    if attempt == 0 {
                        conditional = false
                        continue
                    }
                    break requestLoop
                }
                if Self.isRetryable(http.statusCode) {
                    if attempt == 0 { continue }
                    break requestLoop
                }
                guard http.statusCode == 200,
                      let document = try? TranslationDocument(data: data)
                else { break requestLoop }
                let entry = CacheEntry(
                    data: data,
                    etag: http.value(forHTTPHeaderField: "ETag"),
                    lastModified: http.value(forHTTPHeaderField: "Last-Modified")
                )
                do {
                    let written = try barrier.perform(generation: generation) {
                        try FileManager.default.createDirectory(
                            at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true
                        )
                        try JSONEncoder().encode(entry).write(to: cacheFile, options: .atomic)
                        return true
                    }
                    guard written == true else {
                        return LoadedDocument(document: nil, source: nil, warning: nil, isCancelled: true)
                    }
                    return LoadedDocument(
                        document: document,
                        source: .network,
                        warning: nil,
                        isCancelled: false
                    )
                } catch {
                    return LoadedDocument(
                        document: document,
                        source: .network,
                        warning: "Translation cache could not be written",
                        isCancelled: false
                    )
                }
            } catch is CancellationError {
                return LoadedDocument(
                    document: nil,
                    source: nil,
                    warning: nil,
                    isCancelled: true
                )
            } catch let error as URLError {
                if error.code == .cancelled || Task.isCancelled {
                    return LoadedDocument(
                        document: nil,
                        source: nil,
                        warning: nil,
                        isCancelled: true
                    )
                }
                if attempt == 0, Self.isRetryable(error) { continue }
                break requestLoop
            } catch {
                break requestLoop
            }
        }
        return LoadedDocument(
            document: cached.document,
            source: cached.document == nil ? nil : .cache,
            warning: "Content Delivery fetch failed; using cached or bundled resources",
            isCancelled: false
        )
    }

    /// 同时读取缓存元数据和经过校验的 APPLE_SDK 文档。
    private static func readCache(at file: URL) -> (
        entry: CacheEntry?,
        document: TranslationDocument?
    ) {
        let entry = (try? Data(contentsOf: file)).flatMap {
            try? JSONDecoder().decode(CacheEntry.self, from: $0)
        }
        return (entry, entry.flatMap { try? TranslationDocument(data: $0.data) })
    }

    /// 只对瞬时 HTTP 状态重试一次。
    private static func isRetryable(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }

    /// 仅重试常见的瞬时网络错误。
    private static func isRetryable(_ error: URLError) -> Bool {
        [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
        ].contains(error.code)
    }

    /// 生成不依赖进程随机种子的稳定文件名。
    private static func stableHash(_ value: String) -> String {
        let offset: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let hash = value.utf8.reduce(offset) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(hash, radix: 16)
    }
}
