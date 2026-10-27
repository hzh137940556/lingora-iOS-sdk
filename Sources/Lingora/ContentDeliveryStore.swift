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

/// 隔离 Content Delivery 的磁盘与网络 I/O。
actor ContentDeliveryStore {
    private let cacheDirectory: URL
    private let session: URLSession
    private let appVersion: String

    /// 注入网络会话和缓存目录，便于隔离测试。
    init(cacheDirectory: URL, session: URLSession, appVersion: String) {
        self.cacheDirectory = cacheDirectory
        self.session = session
        self.appVersion = appVersion
    }

    /// 加载一个 language/table，网络失败时保留最后有效缓存。
    func load(baseURL: URL, language: String, table: String) async -> LoadedDocument {
        let url = Self.documentURL(baseURL: baseURL, language: language, table: table)
        let cacheFile = cacheFile(for: url)
        return await Self.fetch(url: url, cacheFile: cacheFile, session: session)
    }

    /// 只读取一个 language/table 的有效磁盘缓存，不发起网络请求。
    func cached(baseURL: URL, language: String, table: String) -> LoadedDocument? {
        let url = Self.documentURL(baseURL: baseURL, language: language, table: table)
        guard let document = Self.readCache(at: cacheFile(for: url)).document else {
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
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
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
        session: URLSession
    ) async -> LoadedDocument {
        let cached = readCache(at: cacheFile)
        var conditional = true
        requestLoop: for attempt in 0...1 {
            if Task.isCancelled {
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
                if Task.isCancelled {
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
                    try FileManager.default.createDirectory(
                        at: cacheFile.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try JSONEncoder().encode(entry).write(to: cacheFile, options: .atomic)
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
