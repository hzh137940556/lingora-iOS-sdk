// 使用固定 CLDR 数据选择普通数值的 cardinal plural category。
import Foundation

/// 将 Double 转为 CLDR operands；不使用私有 ICU API，也不推断 compact notation。
enum PluralRules {
    /// 绝对值和小数位来自最短十进制表示；Double 不保留调用方输入的可见尾零。
    struct Operands {
        let n: Double
        let i: Double
        let v: Double
        let w: Double
        let f: Double
        let t: Double
        let fractionValue: UInt64
        let c: Double = 0
        let e: Double = 0

        /// 展开科学计数表示，避免将普通小数误判为整数或 compact 数字。
        init(_ number: Double) {
            n = abs(number)
            i = n.rounded(.towardZero)
            let parts = String(n).lowercased().split(separator: "e")
            let exponent = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
            let mantissa = parts[0].split(separator: ".")
            let digits = mantissa.joined()
            let decimalPosition = mantissa[0].count + exponent
            let fraction: String
            if decimalPosition <= 0 {
                fraction = String(repeating: "0", count: -decimalPosition) + digits
            } else if decimalPosition < digits.count {
                fraction = String(digits.dropFirst(decimalPosition))
            } else {
                fraction = ""
            }
            let significant = String(fraction.reversed().drop(while: { $0 == "0" }).reversed())
            v = Double(significant.count)
            w = v
            fractionValue = UInt64(significant) ?? 0
            f = Double(fractionValue)
            t = f
        }
    }

    /// CLDR 的 = 集合只包含整数；例如 n = 3..10 不包含 3.5。
    static func matches(_ value: Double, _ ranges: [ClosedRange<Double>]) -> Bool {
        value.rounded(.towardZero) == value && ranges.contains { $0.contains(value) }
    }

    /// 地区特例优先于基础语言，负数按绝对值选择；未知语言使用 CLDR root。
    static func category(for number: Double, locale: Locale) -> String {
        guard number.isFinite, abs(number) < Double(Int.max) else { return "other" }
        let operands = Operands(number)
        let language = locale.language.languageCode?.identifier.lowercased() ?? "root"
        if let region = locale.region?.identifier.lowercased(),
           let category = generatedCategory(operands, tag: "\(language)-\(region)") {
            return category
        }
        if let script = locale.language.script?.identifier.lowercased(),
           let category = generatedCategory(operands, tag: "\(language)-\(script)") {
            return category
        }
        return generatedCategory(operands, tag: language) ?? "other"
    }
}
