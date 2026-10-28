// 由 scripts/generate_plural_rules.py 从 Unicode CLDR 49 生成；勿手工编辑。
// 数据许可见 THIRD_PARTY_NOTICES.md。
import Foundation

extension PluralRules {
    /// 按完整标签优先、基础语言其次选择 CLDR cardinal 规则。
    static func generatedCategory(_ o: Operands, tag: String) -> String? {
        switch tag {
        case "bm", "bo", "dz", "hnj", "id", "ig", "ii", "in", "ja", "jbo", "jv", "jw", "kde", "kea", "km", "ko", "lkt", "lo", "ms", "my", "nqo", "osa", "root", "sah", "ses", "sg", "su", "th", "to", "tpi", "wo", "yo", "yue", "zh":
            return "other"
        case "am", "as", "bn", "doi", "fa", "gu", "hi", "kn", "kok", "kok-latn", "pcm", "tg", "vi", "zu":
            if (matches(o.i, [0...0])) || (matches(o.n, [1...1])) { return "one" }
            return "other"
        case "ff", "hy", "kab":
            if (matches(o.i, [0...0, 1...1])) { return "one" }
            return "other"
        case "ast", "de", "en", "et", "fi", "fy", "ia", "ie", "io", "ji", "lij", "nl", "sc", "sv", "sw", "ur", "yi":
            if (matches(o.i, [1...1]) && matches(o.v, [0...0])) { return "one" }
            return "other"
        case "si":
            if (matches(o.n, [0...0, 1...1])) || (matches(o.i, [0...0]) && matches(o.f, [1...1])) { return "one" }
            return "other"
        case "ak", "bho", "csw", "guw", "ln", "mg", "nso", "pa", "ti", "wa":
            if (matches(o.n, [0...1])) { return "one" }
            return "other"
        case "tzm":
            if (matches(o.n, [0...1])) || (matches(o.n, [11...99])) { return "one" }
            return "other"
        case "af", "an", "asa", "az", "bal", "bem", "bez", "bg", "brx", "ce", "cgg", "chr", "ckb", "dv", "ee", "el", "eo", "eu", "fo", "fur", "gsw", "ha", "haw", "hu", "jgo", "jmc", "ka", "kaj", "kcg", "kk", "kkj", "kl", "ks", "ksb", "ku", "ky", "lb", "lg", "mas", "mgo", "ml", "mn", "mr", "nah", "nb", "nd", "ne", "nn", "nnh", "no", "nr", "ny", "nyn", "om", "or", "os", "pap", "ps", "rm", "rof", "rwk", "saq", "sd", "sdh", "seh", "sn", "so", "sq", "ss", "ssy", "st", "syr", "ta", "te", "teo", "tig", "tk", "tn", "tr", "ts", "ug", "uz", "ve", "vo", "vun", "wae", "xh", "xog":
            if (matches(o.n, [1...1])) { return "one" }
            return "other"
        case "da":
            if (matches(o.n, [1...1])) || (!matches(o.t, [0...0]) && matches(o.i, [0...0, 1...1])) { return "one" }
            return "other"
        case "is":
            if (matches(o.t, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [11...11])) || (matches(Double(o.fractionValue % 10), [1...1]) && !matches(Double(o.fractionValue % 100), [11...11])) { return "one" }
            return "other"
        case "mk":
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [11...11])) || (matches(Double(o.fractionValue % 10), [1...1]) && !matches(Double(o.fractionValue % 100), [11...11])) { return "one" }
            return "other"
        case "ceb", "fil", "tl":
            if (matches(o.v, [0...0]) && matches(o.i, [1...1, 2...2, 3...3])) || (matches(o.v, [0...0]) && !matches(o.i.truncatingRemainder(dividingBy: 10), [4...4, 6...6, 9...9])) || (!matches(o.v, [0...0]) && !matches(Double(o.fractionValue % 10), [4...4, 6...6, 9...9])) { return "one" }
            return "other"
        case "lv", "prg":
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [0...0])) || (matches(o.n.truncatingRemainder(dividingBy: 100), [11...19])) || (matches(o.v, [2...2]) && matches(Double(o.fractionValue % 100), [11...19])) { return "zero" }
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...11])) || (matches(o.v, [2...2]) && matches(Double(o.fractionValue % 10), [1...1]) && !matches(Double(o.fractionValue % 100), [11...11])) || (!matches(o.v, [2...2]) && matches(Double(o.fractionValue % 10), [1...1])) { return "one" }
            return "other"
        case "lag":
            if (matches(o.n, [0...0])) { return "zero" }
            if (matches(o.i, [0...0, 1...1]) && !matches(o.n, [0...0])) { return "one" }
            return "other"
        case "blo", "cv", "ksh":
            if (matches(o.n, [0...0])) { return "zero" }
            if (matches(o.n, [1...1])) { return "one" }
            return "other"
        case "he", "iw":
            if (matches(o.i, [1...1]) && matches(o.v, [0...0])) || (matches(o.i, [0...0]) && !matches(o.v, [0...0])) { return "one" }
            if (matches(o.i, [2...2]) && matches(o.v, [0...0])) { return "two" }
            return "other"
        case "iu", "naq", "sat", "se", "sma", "smi", "smj", "smn", "sms":
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n, [2...2])) { return "two" }
            return "other"
        case "shi":
            if (matches(o.i, [0...0])) || (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n, [2...10])) { return "few" }
            return "other"
        case "mo", "ro":
            if (matches(o.i, [1...1]) && matches(o.v, [0...0])) { return "one" }
            if (!matches(o.v, [0...0])) || (matches(o.n, [0...0])) || (!matches(o.n, [1...1]) && matches(o.n.truncatingRemainder(dividingBy: 100), [1...19])) { return "few" }
            return "other"
        case "bs", "hr", "sh", "sr":
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [11...11])) || (matches(Double(o.fractionValue % 10), [1...1]) && !matches(Double(o.fractionValue % 100), [11...11])) { return "one" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [2...4]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [12...14])) || (matches(Double(o.fractionValue % 10), [2...4]) && !matches(Double(o.fractionValue % 100), [12...14])) { return "few" }
            return "other"
        case "fr", "pt":
            if (matches(o.i, [0...1])) { return "one" }
            if (matches(o.e, [0...0]) && !matches(o.i, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 1000000), [0...0]) && matches(o.v, [0...0])) || (!matches(o.e, [0...5])) { return "many" }
            return "other"
        case "ca", "gl", "it", "lld", "pt-pt", "scn", "vec":
            if (matches(o.i, [1...1]) && matches(o.v, [0...0])) { return "one" }
            if (matches(o.e, [0...0]) && !matches(o.i, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 1000000), [0...0]) && matches(o.v, [0...0])) || (!matches(o.e, [0...5])) { return "many" }
            return "other"
        case "es":
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.e, [0...0]) && !matches(o.i, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 1000000), [0...0]) && matches(o.v, [0...0])) || (!matches(o.e, [0...5])) { return "many" }
            return "other"
        case "gd":
            if (matches(o.n, [1...1, 11...11])) { return "one" }
            if (matches(o.n, [2...2, 12...12])) { return "two" }
            if (matches(o.n, [3...10, 13...19])) { return "few" }
            return "other"
        case "sl":
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [1...1])) { return "one" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [2...2])) { return "two" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [3...4])) || (!matches(o.v, [0...0])) { return "few" }
            return "other"
        case "dsb", "hsb":
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [1...1])) || (matches(Double(o.fractionValue % 100), [1...1])) { return "one" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [2...2])) || (matches(Double(o.fractionValue % 100), [2...2])) { return "two" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [3...4])) || (matches(Double(o.fractionValue % 100), [3...4])) { return "few" }
            return "other"
        case "cs", "sk":
            if (matches(o.i, [1...1]) && matches(o.v, [0...0])) { return "one" }
            if (matches(o.i, [2...4]) && matches(o.v, [0...0])) { return "few" }
            if (!matches(o.v, [0...0])) { return "many" }
            return "other"
        case "pl":
            if (matches(o.i, [1...1]) && matches(o.v, [0...0])) { return "one" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [2...4]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [12...14])) { return "few" }
            if (matches(o.v, [0...0]) && !matches(o.i, [1...1]) && matches(o.i.truncatingRemainder(dividingBy: 10), [0...1])) || (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [5...9])) || (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [12...14])) { return "many" }
            return "other"
        case "be":
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...11])) { return "one" }
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [2...4]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [12...14])) { return "few" }
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [0...0])) || (matches(o.n.truncatingRemainder(dividingBy: 10), [5...9])) || (matches(o.n.truncatingRemainder(dividingBy: 100), [11...14])) { return "many" }
            return "other"
        case "lt":
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...19])) { return "one" }
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [2...9]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...19])) { return "few" }
            if (!matches(o.f, [0...0])) { return "many" }
            return "other"
        case "ru", "uk":
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [11...11])) { return "one" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [2...4]) && !matches(o.i.truncatingRemainder(dividingBy: 100), [12...14])) { return "few" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [0...0])) || (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [5...9])) || (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [11...14])) { return "many" }
            return "other"
        case "sgs":
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...11])) { return "one" }
            if (matches(o.n, [2...2])) { return "two" }
            if (!matches(o.n, [2...2]) && matches(o.n.truncatingRemainder(dividingBy: 10), [2...9]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...19])) { return "few" }
            if (!matches(o.f, [0...0])) { return "many" }
            return "other"
        case "br":
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [1...1]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [11...11, 71...71, 91...91])) { return "one" }
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [2...2]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [12...12, 72...72, 92...92])) { return "two" }
            if (matches(o.n.truncatingRemainder(dividingBy: 10), [3...4, 9...9]) && !matches(o.n.truncatingRemainder(dividingBy: 100), [10...19, 70...79, 90...99])) { return "few" }
            if (!matches(o.n, [0...0]) && matches(o.n.truncatingRemainder(dividingBy: 1000000), [0...0])) { return "many" }
            return "other"
        case "mt":
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n, [2...2])) { return "two" }
            if (matches(o.n, [0...0])) || (matches(o.n.truncatingRemainder(dividingBy: 100), [3...10])) { return "few" }
            if (matches(o.n.truncatingRemainder(dividingBy: 100), [11...19])) { return "many" }
            return "other"
        case "ga":
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n, [2...2])) { return "two" }
            if (matches(o.n, [3...6])) { return "few" }
            if (matches(o.n, [7...10])) { return "many" }
            return "other"
        case "gv":
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [1...1])) { return "one" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 10), [2...2])) { return "two" }
            if (matches(o.v, [0...0]) && matches(o.i.truncatingRemainder(dividingBy: 100), [0...0, 20...20, 40...40, 60...60, 80...80])) { return "few" }
            if (!matches(o.v, [0...0])) { return "many" }
            return "other"
        case "kw":
            if (matches(o.n, [0...0])) { return "zero" }
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n.truncatingRemainder(dividingBy: 100), [2...2, 22...22, 42...42, 62...62, 82...82])) || (matches(o.n.truncatingRemainder(dividingBy: 1000), [0...0]) && matches(o.n.truncatingRemainder(dividingBy: 100000), [1000...20000, 40000...40000, 60000...60000, 80000...80000])) || (!matches(o.n, [0...0]) && matches(o.n.truncatingRemainder(dividingBy: 1000000), [100000...100000])) { return "two" }
            if (matches(o.n.truncatingRemainder(dividingBy: 100), [3...3, 23...23, 43...43, 63...63, 83...83])) { return "few" }
            if (!matches(o.n, [1...1]) && matches(o.n.truncatingRemainder(dividingBy: 100), [1...1, 21...21, 41...41, 61...61, 81...81])) { return "many" }
            return "other"
        case "ar", "ars":
            if (matches(o.n, [0...0])) { return "zero" }
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n, [2...2])) { return "two" }
            if (matches(o.n.truncatingRemainder(dividingBy: 100), [3...10])) { return "few" }
            if (matches(o.n.truncatingRemainder(dividingBy: 100), [11...99])) { return "many" }
            return "other"
        case "cy":
            if (matches(o.n, [0...0])) { return "zero" }
            if (matches(o.n, [1...1])) { return "one" }
            if (matches(o.n, [2...2])) { return "two" }
            if (matches(o.n, [3...3])) { return "few" }
            if (matches(o.n, [6...6])) { return "many" }
            return "other"
        default: return nil
        }
    }
}
