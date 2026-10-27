// 按调用方 Bundle、namespace 和语言读取随应用分发的 APPLE_SDK 文档。
import Foundation

/// 缓存不可变 Bundle 文档和缺失结果，避免每次翻译重复读取磁盘。
@MainActor
final class BundledTranslationStore {
    private enum Entry {
        case missing
        case document(TranslationDocument)
    }

    private var entries: [URL: Entry] = [:]

    /// 按精确语言、基础语言和 Bundle 默认语言逐 Key 查找，坏文件继续回退。
    func template(
        for key: String,
        bundle: Bundle,
        directory: String,
        language: String,
        table: String?,
        locale: Locale,
        arguments: [CVarArg]
    ) -> String? {
        guard let root = bundle.resourceURL,
              isSafeComponent(directory),
              table.map(isSafeComponent) ?? true
        else { return nil }
        var languages = [String]()
        let parts = language.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        for length in stride(from: parts.count, through: 1, by: -1) {
            languages.append(parts.prefix(length).joined(separator: "-"))
        }
        if let developmentLanguage = bundle.developmentLocalization {
            languages.append(developmentLanguage)
        }
        var visited = Set<String>()
        for candidate in languages where isSafeComponent(candidate) && visited.insert(candidate).inserted {
            var url = root.appendingPathComponent(directory, isDirectory: true)
            if let table { url.appendPathComponent(table, isDirectory: true) }
            url.appendPathComponent(candidate + ".json")
            if entries[url] == nil {
                // 在读取前限制文件大小；解析器继续执行完整文档校验。
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if let size, size <= TranslationDocument.maximumBytes,
                   let data = try? Data(contentsOf: url),
                   let document = try? TranslationDocument(data: data) {
                    entries[url] = .document(document)
                } else {
                    entries[url] = .missing
                }
            }
            if case .document(let document) = entries[url],
               let template = document.template(
                   for: key,
                   locale: candidate == language ? locale : Locale(identifier: candidate),
                   arguments: arguments
               ) {
                return template
            }
        }
        return nil
    }

    /// 防止 namespace 或 Bundle 元数据使资源查找越过指定目录。
    private func isSafeComponent(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", options: .regularExpression) != nil
    }
}
