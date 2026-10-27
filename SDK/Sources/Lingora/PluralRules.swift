// 实现 APPLE_SDK 使用的 CLDR cardinal plural category。
import Foundation

/// 按 Tolgee Swift SDK 覆盖的语言集合选择 plural category。
enum PluralRules {
    /// 根据 locale、整数、负数和小数返回远端 plural key。
    static func category(for number: Double, locale: Locale) -> String {
        guard number.isFinite, number >= 0, number < Double(Int.max) else { return "other" }
        let language = locale.language.languageCode?.identifier
            ?? locale.identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
            ?? "en"
        let n = number
        let i = Int(abs(number))
        let v = fractionDigits(number)
        let f = fractionValue(number)
        let e = scientificExponent(number)

        switch language {
        case "ja", "ko", "zh", "th", "vi", "id", "ms", "my", "km", "lo":
            return "other"
        case "en", "de", "nl", "sv", "da", "no", "nb", "nn", "fi", "et", "eu",
             "gl", "el", "bg", "sq", "ta", "te", "ml", "mr", "ur", "ne", "sw", "af":
            return i == 1 && v == 0 ? "one" : "other"
        case "fr":
            if i == 0 || i == 1 { return "one" }
            return isMillion(i: i, v: v, exponent: e) ? "many" : "other"
        case "es":
            if n == 1 { return "one" }
            return isMillion(i: i, v: v, exponent: e) ? "many" : "other"
        case "pt":
            if (0...1).contains(i) { return "one" }
            return isMillion(i: i, v: v, exponent: e) ? "many" : "other"
        case "it", "ca":
            if i == 1 && v == 0 { return "one" }
            return isMillion(i: i, v: v, exponent: e) ? "many" : "other"
        case "cs", "sk":
            if i == 1 && v == 0 { return "one" }
            if (2...4).contains(i) && v == 0 { return "few" }
            return v != 0 ? "many" : "other"
        case "pl":
            if v != 0 { return "other" }
            if i == 1 { return "one" }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return "few" }
            if i != 1 && (i % 10 == 0 || i % 10 == 1)
                || (5...9).contains(i % 10)
                || (12...14).contains(i % 100) { return "many" }
            return "other"
        case "ru", "uk":
            return eastSlavic(i: i, v: v)
        case "be":
            if i % 10 == 1 && i % 100 != 11 { return "one" }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return "few" }
            if i % 10 == 0 || (5...9).contains(i % 10) || (11...14).contains(i % 100) {
                return "many"
            }
            return "other"
        case "hr", "sr", "bs":
            if v == 0 && i % 10 == 1 && i % 100 != 11
                || f % 10 == 1 && f % 100 != 11 { return "one" }
            if v == 0 && (2...4).contains(i % 10) && !(12...14).contains(i % 100)
                || (2...4).contains(f % 10) && !(12...14).contains(f % 100) { return "few" }
            return "other"
        case "sl":
            if v == 0 && i % 100 == 1 { return "one" }
            if v == 0 && i % 100 == 2 { return "two" }
            if v != 0 || (3...4).contains(i % 100) { return "few" }
            return "other"
        case "lt":
            if i % 10 == 1 && !(11...19).contains(i % 100) { return "one" }
            if (2...9).contains(i % 10) && !(11...19).contains(i % 100) { return "few" }
            return f != 0 ? "many" : "other"
        case "lv":
            if i % 10 == 0 || (11...19).contains(i % 100)
                || v == 2 && (11...19).contains(f % 100) { return "zero" }
            if i % 10 == 1 && i % 100 != 11
                || v == 2 && f % 10 == 1 && f % 100 != 11
                || v != 2 && f % 10 == 1 { return "one" }
            return "other"
        case "he":
            if i == 1 && v == 0 || i == 0 && v != 0 { return "one" }
            return i == 2 && v == 0 ? "two" : "other"
        case "ar":
            if n == 0 { return "zero" }
            if n == 1 { return "one" }
            if n == 2 { return "two" }
            if (3...10).contains(i % 100) { return "few" }
            if (11...99).contains(i % 100) { return "many" }
            return "other"
        case "cy":
            if n == 0 { return "zero" }
            if n == 1 { return "one" }
            if n == 2 { return "two" }
            if n == 3 { return "few" }
            return n == 6 ? "many" : "other"
        case "ro":
            if i == 1 && v == 0 { return "one" }
            if v != 0 || n == 0 || n != 1 && (1...19).contains(i % 100) { return "few" }
            return "other"
        case "mk":
            if v == 0 && i % 10 == 1 && i % 100 != 11
                || f % 10 == 1 && f % 100 != 11 { return "one" }
            return "other"
        case "mt":
            if n == 1 { return "one" }
            if n == 2 { return "two" }
            if n == 0 || (3...10).contains(i % 100) { return "few" }
            return (11...19).contains(i % 100) ? "many" : "other"
        case "ga":
            if n == 1 { return "one" }
            if n == 2 { return "two" }
            if (3...6).contains(n) { return "few" }
            return (7...10).contains(n) ? "many" : "other"
        case "gd":
            if n == 1 || n == 11 { return "one" }
            if n == 2 || n == 12 { return "two" }
            if (3...10).contains(n) || (13...19).contains(n) { return "few" }
            return "other"
        case "br":
            if i % 10 == 1 && ![11, 71, 91].contains(i % 100) { return "one" }
            if i % 10 == 2 && ![12, 72, 92].contains(i % 100) { return "two" }
            if [3, 4, 9].contains(i % 10)
                && !(10...19).contains(i % 100)
                && !(70...79).contains(i % 100)
                && !(90...99).contains(i % 100) { return "few" }
            return n != 0 && i % 1_000_000 == 0 ? "many" : "other"
        case "hi", "bn", "gu", "kn", "fa":
            return i == 0 || n == 1 ? "one" : "other"
        case "pa":
            return (0...1).contains(n) ? "one" : "other"
        case "si":
            return n == 0 || n == 1 || i == 0 && f == 1 ? "one" : "other"
        case "hu", "tr", "az", "ka", "hy", "is":
            return n == 1 ? "one" : "other"
        default:
            return i == 1 && v == 0 ? "one" : "other"
        }
    }

    /// 解析 Double 文本中的有效小数位数。
    private static func fractionDigits(_ number: Double) -> Int {
        let text = String(number)
        guard let dot = text.firstIndex(of: "."), !text.contains("e"), !text.contains("E") else {
            return 0
        }
        let fraction = text[text.index(after: dot)...]
        return fraction.allSatisfy { $0 == "0" } ? 0 : fraction.count
    }

    /// 将可见小数部分转换为整数。
    private static func fractionValue(_ number: Double) -> Int {
        let text = String(number)
        guard let dot = text.firstIndex(of: "."), !text.contains("e"), !text.contains("E") else {
            return 0
        }
        return Int(text[text.index(after: dot)...]) ?? 0
    }

    /// 返回 CLDR 百万量级规则使用的十进制指数。
    private static func scientificExponent(_ number: Double) -> Int {
        number == 0 ? 0 : Int(floor(log10(abs(number))))
    }

    /// 判断法语、葡萄牙语等语言的 many 条件。
    private static func isMillion(i: Int, v: Int, exponent: Int) -> Bool {
        exponent == 0 && i != 0 && i % 1_000_000 == 0 && v == 0
            || exponent < 0
            || exponent > 5
    }

    /// 复用俄语和乌克兰语的整数模规则。
    private static func eastSlavic(i: Int, v: Int) -> String {
        guard v == 0 else { return "other" }
        if i % 10 == 1 && i % 100 != 11 { return "one" }
        if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return "few" }
        if i % 10 == 0 || (5...9).contains(i % 10) || (11...14).contains(i % 100) {
            return "many"
        }
        return "other"
    }
}
