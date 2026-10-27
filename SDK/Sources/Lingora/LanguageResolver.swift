// 按 Android 的精确、显式 script/region、基础语言顺序解析远端语言。
import Foundation

/// Apple Delivery 无语言目录，由调用方提供已发布标签；nil 表示未知目录。
enum LanguageResolver {
    /// 接受常用 BCP-47 标签，拒绝路径及 Locale 扩展语法。
    static func validTag(_ tag: String) -> Bool {
        tag.count <= 80 && tag.range(of: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil
    }

    /// 大小写等价标签视为重复，避免目录顺序影响命中。
    static func validList(_ tags: [String]) -> Bool {
        tags.count <= 1000 && tags.allSatisfy(validTag) && Set(tags.map { $0.lowercased() }).count == tags.count
    }

    /// 只使用标签显式携带的文字系统，不推断或跨地区选择；无匹配时返回配置的默认语言。
    static func resolve(_ requested: String, available: [String]?, defaultLanguage: String?) -> String? {
        guard let available else { return requested }
        let parts = requested.split(separator: "-").map(String.init)
        guard let language = parts.first else { return defaultLanguage }
        var index = 1
        let script = index < parts.count && parts[index].count == 4 && parts[index].allSatisfy(\.isLetter) ? parts[index] : nil
        if script != nil { index += 1 }
        let region = index < parts.count && ((parts[index].count == 2 && parts[index].allSatisfy(\.isLetter))
            || (parts[index].count == 3 && parts[index].allSatisfy(\.isNumber))) ? parts[index] : nil
        if region != nil { index += 1 }
        let variant = parts.dropFirst(index).prefix { $0.count > 1 }.joined(separator: "-")
        let candidates = [requested,
                          [language, script, region].compactMap { $0 }.joined(separator: "-"),
                          [language, script].compactMap { $0 }.joined(separator: "-"),
                          [language, region, variant.isEmpty ? nil : variant].compactMap { $0 }.joined(separator: "-"),
                          [language, region].compactMap { $0 }.joined(separator: "-"), language]
        for candidate in candidates {
            if let match = available.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) { return match }
        }
        return defaultLanguage
    }
}
