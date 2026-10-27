// 校验可选语言目录并按语言、文字系统和地区确定远端语言。
import Foundation

/// 配置可选语言匹配；不传此配置时保持精确请求。
public struct LingoraLanguageOptions: Sendable {
    public let availableLanguages: [String]
    public let defaultLanguage: String?
    public let manifestFileName: String?

    /// 静态列表优先；manifest 仅用于没有静态列表时，文件名必须位于 Delivery 根目录。
    public init(availableLanguages: [String] = [], defaultLanguage: String? = nil, manifestFileName: String? = nil) {
        self.availableLanguages = availableLanguages
        self.defaultLanguage = defaultLanguage
        self.manifestFileName = manifestFileName
    }
}

/// 解析现有 Delivery 的 locales 字段，不依赖 Android 特有资源格式。
struct LanguageManifest: Decodable, Sendable {
    let locales: [String]

    /// 限制大小、重复项和标签，避免不可信目录构造路径。
    init(data: Data) throws {
        guard data.count <= 256 * 1024 else { throw TranslationDocumentError.tooLarge }
        self = try JSONDecoder().decode(Self.self, from: data)
        guard LanguageResolver.validList(locales) else { throw TranslationDocumentError.invalid }
    }
}

/// 以确定顺序选择一个文档语言，不进行逐 key 的跨语言混合。
enum LanguageResolver {
    /// 接受常用 BCP-47 标签，拒绝路径及 Locale 扩展语法。
    static func validTag(_ tag: String) -> Bool {
        tag.count <= 80 && tag.range(of: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil
    }

    /// 大小写等价标签视为重复，避免目录顺序影响命中。
    static func validList(_ tags: [String]) -> Bool {
        tags.count <= 1000 && tags.allSatisfy(validTag) && Set(tags.map { $0.lowercased() }).count == tags.count
    }

    /// 精确、同文字系统无地区、同文字系统地区变体、基础语言、显式默认语言。
    static func resolve(_ requested: String, available: [String], defaultLanguage: String?) -> String {
        guard !available.isEmpty else { return requested }
        if let exact = available.first(where: { $0.caseInsensitiveCompare(requested) == .orderedSame }) { return exact }
        let requestedLocale = Locale(identifier: requested)
        let language = requestedLocale.language.languageCode?.identifier
        let script = requestedLocale.language.script?.identifier
        let sameLanguage = available.filter { Locale(identifier: $0).language.languageCode?.identifier == language }
        let compatible = sameLanguage.filter { Locale(identifier: $0).language.script?.identifier == script }
        let ranked = compatible.sorted {
            let left = Locale(identifier: $0).region == nil
            let right = Locale(identifier: $1).region == nil
            return left != right ? left : $0 < $1
        }
        if let match = ranked.first { return match }
        // 基础语言也必须拥有相同的推定文字系统，不能将繁体中文退到默认简体 zh。
        if let fallback = defaultLanguage,
           let match = available.first(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) { return match }
        return requested
    }
}
