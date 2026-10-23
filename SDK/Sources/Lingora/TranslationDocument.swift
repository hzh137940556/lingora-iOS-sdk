// 解析 APPLE_SDK JSON 并选择受支持语言的 plural 变体。
import Foundation

/// 表示无效或超限的远端语言包。
enum TranslationDocumentError: Error {
    case invalid
    case tooLarge
}

/// 保存普通文本或 plural 变体。
enum TranslationValue: Decodable, Sendable, Equatable {
    case text(String)
    case plural([String: String])

    private struct Variations: Decodable {
        let plural: [String: String]
    }

    private struct StructuredEntry: Decodable {
        let variations: Variations
    }

    /// 严格解析 Lingora APPLE_SDK 的两种公开数据形状。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        let forms = try container.decode(StructuredEntry.self).variations.plural
        let supported = Set(["zero", "one", "two", "few", "many", "other"])
        guard forms["other"] != nil, Set(forms.keys).isSubset(of: supported) else {
            throw TranslationDocumentError.invalid
        }
        self = .plural(forms)
    }
}

/// 保存一个 language/table 的完整有效文档。
struct TranslationDocument: Sendable, Equatable {
    static let maximumBytes = 10 * 1024 * 1024
    let values: [String: TranslationValue]

    /// 整体校验 JSON 后才允许进入内存或磁盘缓存。
    init(data: Data) throws {
        guard data.count <= Self.maximumBytes else {
            throw TranslationDocumentError.tooLarge
        }
        values = try JSONDecoder().decode([String: TranslationValue].self, from: data)
        guard values.keys.allSatisfy({ !$0.isEmpty }) else {
            throw TranslationDocumentError.invalid
        }
    }

    /// 返回普通文本或按 locale/count 选择后的 plural 模板。
    func template(for key: String, locale: Locale, arguments: [CVarArg]) -> String? {
        switch values[key] {
        case .text(let value):
            return value
        case .plural(let forms):
            guard let count = arguments.first.flatMap(numericValue) else { return nil }
            return forms[PluralRules.category(for: count, locale: locale)] ?? forms["other"]
        case nil:
            return nil
        }
    }
}

/// 将首个格式化参数安全转换为 plural 计数。
private func numericValue(_ value: CVarArg) -> Double? {
    switch value {
    case let number as Int: Double(number)
    case let number as Int8: Double(number)
    case let number as Int16: Double(number)
    case let number as Int32: Double(number)
    case let number as Int64: Double(number)
    case let number as UInt: Double(number)
    case let number as UInt8: Double(number)
    case let number as UInt16: Double(number)
    case let number as UInt32: Double(number)
    case let number as UInt64: Double(number)
    case let number as Double: number
    case let number as Float: Double(number)
    case let number as NSNumber: number.doubleValue
    default: nil
    }
}
