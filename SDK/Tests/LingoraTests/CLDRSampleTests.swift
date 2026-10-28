// 由 CLDR 49 官方普通数值样例生成；compact 和可见尾零不属于 Double API。
import XCTest
@testable import Lingora

final class CLDRSampleTests: XCTestCase {
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup0() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (1.5, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (15, "other")
        ]
        for tag in ["bm", "bo", "dz", "hnj", "id", "ig", "ii", "in", "ja", "jbo", "jv", "jw", "kde", "kea", "km", "ko", "lkt", "lo", "ms", "my", "nqo", "osa", "root", "sah", "ses", "sg", "su", "th", "to", "tpi", "wo", "yo", "yue", "zh"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup1() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (0.04, "one"),
            (1, "one"),
            (1.1, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "other"),
            (2.6, "other")
        ]
        for tag in ["am", "as", "bn", "doi", "fa", "gu", "hi", "kn", "kok", "kok-Latn", "pcm", "tg", "vi", "zu"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup2() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (1, "one"),
            (1.5, "one"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "other"),
            (3.5, "other")
        ]
        for tag in ["ff", "hy", "kab"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup3() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (1, "one"),
            (1.5, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (16, "other"),
            (2, "other")
        ]
        for tag in ["ast", "de", "en", "et", "fi", "fy", "ia", "ie", "io", "ji", "lij", "nl", "sc", "sv", "sw", "ur", "yi"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup4() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (0.0001, "one"),
            (0.001, "one"),
            (0.01, "one"),
            (0.1, "one"),
            (0.2, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.8, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "other")
        ]
        for tag in ["si"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup5() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "other")
        ]
        for tag in ["ak", "bho", "csw", "guw", "ln", "mg", "nso", "pa", "ti", "wa"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup6() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (10, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (106, "other"),
            (11, "one"),
            (2, "other"),
            (24, "one")
        ]
        for tag in ["tzm"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup7() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.6, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (16, "other"),
            (2, "other")
        ]
        for tag in ["af", "an", "asa", "az", "bal", "bem", "bez", "bg", "brx", "ce", "cgg", "chr", "ckb", "dv", "ee", "el", "eo", "eu", "fo", "fur", "gsw", "ha", "haw", "hu", "jgo", "jmc", "ka", "kaj", "kcg", "kk", "kkj", "kl", "ks", "ksb", "ku", "ky", "lb", "lg", "mas", "mgo", "ml", "mn", "mr", "nah", "nb", "nd", "ne", "nn", "nnh", "no", "nr", "ny", "nyn", "om", "or", "os", "pap", "ps", "rm", "rof", "rwk", "saq", "sd", "sdh", "seh", "sn", "so", "sq", "ss", "ssy", "st", "syr", "ta", "te", "teo", "tig", "tk", "tn", "tr", "ts", "ug", "uz", "ve", "vo", "vun", "wae", "xh", "xog"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup8() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "one"),
            (1, "one"),
            (1.6, "one"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (16, "other"),
            (2, "other"),
            (3.4, "other")
        ]
        for tag in ["da"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup9() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "one"),
            (0.2, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "one"),
            (1.2, "other"),
            (1.8, "other"),
            (10.1, "one"),
            (100, "other"),
            (100.1, "one"),
            (1000, "other"),
            (1000.1, "one"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (101, "one"),
            (16, "other"),
            (2, "other"),
            (2.1, "one"),
            (21, "one"),
            (3.1, "one"),
            (31, "one"),
            (4.1, "one"),
            (41, "one"),
            (5.1, "one"),
            (51, "one"),
            (6.1, "one"),
            (61, "one"),
            (7.1, "one"),
            (71, "one"),
            (81, "one")
        ]
        for tag in ["is"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup10() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "one"),
            (0.2, "other"),
            (1, "one"),
            (1.1, "one"),
            (1.2, "other"),
            (1.7, "other"),
            (10.1, "one"),
            (100, "other"),
            (100.1, "one"),
            (1000, "other"),
            (1000.1, "one"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (101, "one"),
            (16, "other"),
            (2, "other"),
            (2.1, "one"),
            (21, "one"),
            (3.1, "one"),
            (31, "one"),
            (4.1, "one"),
            (41, "one"),
            (5.1, "one"),
            (51, "one"),
            (6.1, "one"),
            (61, "one"),
            (7.1, "one"),
            (71, "one"),
            (81, "one")
        ]
        for tag in ["mk"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup11() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (0.3, "one"),
            (0.4, "other"),
            (0.5, "one"),
            (0.6, "other"),
            (0.7, "one"),
            (0.8, "one"),
            (0.9, "other"),
            (1.3, "one"),
            (1.4, "other"),
            (1.5, "one"),
            (1.6, "other"),
            (1.7, "one"),
            (1.8, "one"),
            (1.9, "other"),
            (10, "one"),
            (10.4, "other"),
            (100, "one"),
            (100.4, "other"),
            (1000, "one"),
            (1000.4, "other"),
            (10000, "one"),
            (100000, "one"),
            (1000000, "one"),
            (1004, "other"),
            (104, "other"),
            (13, "one"),
            (14, "other"),
            (15, "one"),
            (16, "other"),
            (17, "one"),
            (18, "one"),
            (19, "other"),
            (2.1, "one"),
            (2.4, "other"),
            (2.6, "other"),
            (20, "one"),
            (21, "one"),
            (24, "other"),
            (26, "other"),
            (3, "one"),
            (4, "other"),
            (5, "one"),
            (6, "other"),
            (7, "one"),
            (8, "one"),
            (9, "other")
        ]
        for tag in ["ceb", "fil", "tl"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup12() {
        let cases: [(Double, String)] = [
            (0, "zero"),
            (0.1, "one"),
            (0.2, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "one"),
            (1.2, "other"),
            (1.9, "other"),
            (10, "zero"),
            (10.1, "one"),
            (10.2, "other"),
            (100, "zero"),
            (100.1, "one"),
            (100.2, "other"),
            (1000, "zero"),
            (1000.1, "one"),
            (1000.2, "other"),
            (10000, "zero"),
            (100000, "zero"),
            (1000000, "zero"),
            (1001, "one"),
            (1002, "other"),
            (101, "one"),
            (102, "other"),
            (2, "other"),
            (2.1, "one"),
            (20, "zero"),
            (21, "one"),
            (22, "other"),
            (29, "other"),
            (3.1, "one"),
            (30, "zero"),
            (31, "one"),
            (4.1, "one"),
            (40, "zero"),
            (41, "one"),
            (5.1, "one"),
            (50, "zero"),
            (51, "one"),
            (6.1, "one"),
            (60, "zero"),
            (61, "one"),
            (7.1, "one"),
            (71, "one"),
            (81, "one"),
            (9, "other")
        ]
        for tag in ["lv", "prg"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup13() {
        let cases: [(Double, String)] = [
            (0, "zero"),
            (0.1, "one"),
            (1, "one"),
            (1.6, "one"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "other"),
            (3.5, "other")
        ]
        for tag in ["lag"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup14() {
        let cases: [(Double, String)] = [
            (0, "zero"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "other")
        ]
        for tag in ["blo", "cv", "ksh"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup15() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.05, "one"),
            (0.9, "one"),
            (1, "one"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "two"),
            (2.5, "other"),
            (3, "other")
        ]
        for tag in ["he", "iw"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup16() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.6, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (17, "other"),
            (2, "two"),
            (3, "other")
        ]
        for tag in ["iu", "naq", "sat", "se", "sma", "smi", "smj", "smn", "sms"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup17() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (0.04, "one"),
            (1, "one"),
            (1.1, "other"),
            (1.9, "other"),
            (10, "few"),
            (10.1, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (11, "other"),
            (2, "few"),
            (2.1, "other"),
            (2.7, "other"),
            (26, "other")
        ]
        for tag in ["shi"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup18() {
        let cases: [(Double, String)] = [
            (0, "few"),
            (1, "one"),
            (1.5, "few"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "few"),
            (101, "few"),
            (16, "few"),
            (2, "few"),
            (20, "other"),
            (35, "other")
        ]
        for tag in ["mo", "ro"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup19() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "one"),
            (0.2, "few"),
            (0.4, "few"),
            (0.5, "other"),
            (1, "one"),
            (1.1, "one"),
            (1.2, "few"),
            (1.4, "few"),
            (1.5, "other"),
            (10.1, "one"),
            (10.2, "few"),
            (100, "other"),
            (100.1, "one"),
            (100.2, "few"),
            (1000, "other"),
            (1000.1, "one"),
            (1000.2, "few"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (1002, "few"),
            (101, "one"),
            (102, "few"),
            (19, "other"),
            (2, "few"),
            (2.1, "one"),
            (2.2, "few"),
            (2.4, "few"),
            (2.5, "other"),
            (2.7, "other"),
            (21, "one"),
            (22, "few"),
            (24, "few"),
            (3.1, "one"),
            (3.2, "few"),
            (3.4, "few"),
            (31, "one"),
            (32, "few"),
            (34, "few"),
            (4, "few"),
            (4.1, "one"),
            (4.2, "few"),
            (4.4, "few"),
            (41, "one"),
            (42, "few"),
            (44, "few"),
            (5, "other"),
            (5.1, "one"),
            (5.2, "few"),
            (51, "one"),
            (52, "few"),
            (54, "few"),
            (6.1, "one"),
            (61, "one"),
            (62, "few"),
            (7.1, "one"),
            (71, "one"),
            (81, "one")
        ]
        for tag in ["bs", "hr", "sh", "sr"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup20() {
        let cases: [(Double, String)] = [
            (0, "one"),
            (1, "one"),
            (1.5, "one"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "many"),
            (17, "other"),
            (2, "other"),
            (3.5, "other")
        ]
        for tag in ["fr", "pt"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup21() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (1, "one"),
            (1.5, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "many"),
            (16, "other"),
            (2, "other")
        ]
        for tag in ["ca", "gl", "it", "lld", "pt-PT", "scn", "vec"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup22() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.6, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "many"),
            (16, "other"),
            (2, "other")
        ]
        for tag in ["es"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup23() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.6, "other"),
            (10, "few"),
            (10.1, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (11, "one"),
            (12, "two"),
            (13, "few"),
            (19, "few"),
            (2, "two"),
            (20, "other"),
            (3, "few"),
            (34, "other")
        ]
        for tag in ["gd"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup24() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (1, "one"),
            (1.5, "few"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (1002, "two"),
            (1003, "few"),
            (101, "one"),
            (102, "two"),
            (103, "few"),
            (104, "few"),
            (19, "other"),
            (2, "two"),
            (201, "one"),
            (202, "two"),
            (203, "few"),
            (204, "few"),
            (3, "few"),
            (301, "one"),
            (302, "two"),
            (303, "few"),
            (304, "few"),
            (4, "few"),
            (401, "one"),
            (402, "two"),
            (403, "few"),
            (404, "few"),
            (5, "other"),
            (501, "one"),
            (502, "two"),
            (503, "few"),
            (504, "few"),
            (601, "one"),
            (602, "two"),
            (603, "few"),
            (604, "few"),
            (701, "one"),
            (702, "two"),
            (703, "few"),
            (704, "few")
        ]
        for tag in ["sl"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup25() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "one"),
            (0.2, "two"),
            (0.3, "few"),
            (0.4, "few"),
            (0.5, "other"),
            (1, "one"),
            (1.1, "one"),
            (1.2, "two"),
            (1.3, "few"),
            (1.4, "few"),
            (1.5, "other"),
            (10.1, "one"),
            (10.2, "two"),
            (10.3, "few"),
            (100, "other"),
            (100.1, "one"),
            (100.2, "two"),
            (100.3, "few"),
            (1000, "other"),
            (1000.1, "one"),
            (1000.2, "two"),
            (1000.3, "few"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (1002, "two"),
            (1003, "few"),
            (101, "one"),
            (102, "two"),
            (103, "few"),
            (104, "few"),
            (19, "other"),
            (2, "two"),
            (2.1, "one"),
            (2.2, "two"),
            (2.3, "few"),
            (2.4, "few"),
            (2.5, "other"),
            (2.7, "other"),
            (201, "one"),
            (202, "two"),
            (203, "few"),
            (204, "few"),
            (3, "few"),
            (3.1, "one"),
            (3.2, "two"),
            (3.3, "few"),
            (3.4, "few"),
            (301, "one"),
            (302, "two"),
            (303, "few"),
            (304, "few"),
            (4, "few"),
            (4.1, "one"),
            (4.2, "two"),
            (4.3, "few"),
            (4.4, "few"),
            (401, "one"),
            (402, "two"),
            (403, "few"),
            (404, "few"),
            (5, "other"),
            (5.1, "one"),
            (5.2, "two"),
            (5.3, "few"),
            (5.4, "few"),
            (501, "one"),
            (502, "two"),
            (503, "few"),
            (504, "few"),
            (6.1, "one"),
            (6.2, "two"),
            (6.3, "few"),
            (6.4, "few"),
            (601, "one"),
            (602, "two"),
            (603, "few"),
            (604, "few"),
            (7.1, "one"),
            (7.2, "two"),
            (7.3, "few"),
            (7.4, "few"),
            (701, "one"),
            (702, "two"),
            (703, "few"),
            (704, "few")
        ]
        for tag in ["dsb", "hsb"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup26() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (1, "one"),
            (1.5, "many"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (19, "other"),
            (2, "few"),
            (4, "few"),
            (5, "other")
        ]
        for tag in ["cs", "sk"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup27() {
        let cases: [(Double, String)] = [
            (0, "many"),
            (1, "one"),
            (1.5, "other"),
            (100, "many"),
            (1000, "many"),
            (10000, "many"),
            (100000, "many"),
            (1000000, "many"),
            (1002, "few"),
            (102, "few"),
            (19, "many"),
            (2, "few"),
            (22, "few"),
            (24, "few"),
            (32, "few"),
            (34, "few"),
            (4, "few"),
            (42, "few"),
            (44, "few"),
            (5, "many"),
            (52, "few"),
            (54, "few"),
            (62, "few")
        ]
        for tag in ["pl"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup28() {
        let cases: [(Double, String)] = [
            (0, "many"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (10.1, "other"),
            (100, "many"),
            (100.1, "other"),
            (1000, "many"),
            (1000.1, "other"),
            (10000, "many"),
            (100000, "many"),
            (1000000, "many"),
            (1001, "one"),
            (1002, "few"),
            (101, "one"),
            (102, "few"),
            (19, "many"),
            (2, "few"),
            (21, "one"),
            (22, "few"),
            (24, "few"),
            (31, "one"),
            (32, "few"),
            (34, "few"),
            (4, "few"),
            (41, "one"),
            (42, "few"),
            (44, "few"),
            (5, "many"),
            (51, "one"),
            (52, "few"),
            (54, "few"),
            (61, "one"),
            (62, "few"),
            (71, "one"),
            (81, "one")
        ]
        for tag in ["be"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup29() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "many"),
            (0.9, "many"),
            (1, "one"),
            (1.1, "many"),
            (1.7, "many"),
            (10, "other"),
            (10.1, "many"),
            (100, "other"),
            (100.1, "many"),
            (1000, "other"),
            (1000.1, "many"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (1002, "few"),
            (101, "one"),
            (102, "few"),
            (2, "few"),
            (20, "other"),
            (21, "one"),
            (22, "few"),
            (29, "few"),
            (30, "other"),
            (31, "one"),
            (40, "other"),
            (41, "one"),
            (50, "other"),
            (51, "one"),
            (60, "other"),
            (61, "one"),
            (71, "one"),
            (81, "one"),
            (9, "few")
        ]
        for tag in ["lt"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup30() {
        let cases: [(Double, String)] = [
            (0, "many"),
            (1, "one"),
            (1.5, "other"),
            (100, "many"),
            (1000, "many"),
            (10000, "many"),
            (100000, "many"),
            (1000000, "many"),
            (1001, "one"),
            (1002, "few"),
            (101, "one"),
            (102, "few"),
            (19, "many"),
            (2, "few"),
            (21, "one"),
            (22, "few"),
            (24, "few"),
            (31, "one"),
            (32, "few"),
            (34, "few"),
            (4, "few"),
            (41, "one"),
            (42, "few"),
            (44, "few"),
            (5, "many"),
            (51, "one"),
            (52, "few"),
            (54, "few"),
            (61, "one"),
            (62, "few"),
            (71, "one"),
            (81, "one")
        ]
        for tag in ["ru", "uk"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup31() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.1, "many"),
            (0.9, "many"),
            (1, "one"),
            (1.1, "many"),
            (1.7, "many"),
            (10, "other"),
            (10.1, "many"),
            (100, "other"),
            (100.1, "many"),
            (1000, "other"),
            (1000.1, "many"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1001, "one"),
            (1002, "few"),
            (101, "one"),
            (102, "few"),
            (2, "two"),
            (20, "other"),
            (21, "one"),
            (22, "few"),
            (29, "few"),
            (3, "few"),
            (30, "other"),
            (31, "one"),
            (32, "few"),
            (40, "other"),
            (41, "one"),
            (50, "other"),
            (51, "one"),
            (60, "other"),
            (61, "one"),
            (71, "one"),
            (81, "one"),
            (9, "few")
        ]
        for tag in ["sgs"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup32() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.6, "other"),
            (10, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "many"),
            (1001, "one"),
            (1002, "two"),
            (1003, "few"),
            (101, "one"),
            (102, "two"),
            (103, "few"),
            (2, "two"),
            (20, "other"),
            (21, "one"),
            (22, "two"),
            (23, "few"),
            (24, "few"),
            (29, "few"),
            (3, "few"),
            (31, "one"),
            (32, "two"),
            (33, "few"),
            (34, "few"),
            (39, "few"),
            (4, "few"),
            (41, "one"),
            (42, "two"),
            (43, "few"),
            (44, "few"),
            (49, "few"),
            (5, "other"),
            (51, "one"),
            (52, "two"),
            (61, "one"),
            (62, "two"),
            (8, "other"),
            (81, "one"),
            (82, "two"),
            (9, "few")
        ]
        for tag in ["br"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup33() {
        let cases: [(Double, String)] = [
            (0, "few"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (10, "few"),
            (10.1, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1003, "few"),
            (1011, "many"),
            (103, "few"),
            (109, "few"),
            (11, "many"),
            (111, "many"),
            (117, "many"),
            (19, "many"),
            (2, "two"),
            (20, "other"),
            (3, "few"),
            (35, "other")
        ]
        for tag in ["mt"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup34() {
        let cases: [(Double, String)] = [
            (0, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.6, "other"),
            (10, "many"),
            (10.1, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (11, "other"),
            (2, "two"),
            (25, "other"),
            (3, "few"),
            (6, "few"),
            (7, "many")
        ]
        for tag in ["ga"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup35() {
        let cases: [(Double, String)] = [
            (0, "few"),
            (1, "one"),
            (1.5, "many"),
            (10, "other"),
            (100, "few"),
            (1000, "few"),
            (10000, "few"),
            (100000, "few"),
            (1000000, "few"),
            (1001, "one"),
            (1002, "two"),
            (1003, "other"),
            (101, "one"),
            (102, "two"),
            (103, "other"),
            (11, "one"),
            (12, "two"),
            (120, "few"),
            (13, "other"),
            (140, "few"),
            (19, "other"),
            (2, "two"),
            (20, "few"),
            (21, "one"),
            (22, "two"),
            (23, "other"),
            (3, "other"),
            (31, "one"),
            (32, "two"),
            (40, "few"),
            (41, "one"),
            (42, "two"),
            (51, "one"),
            (52, "two"),
            (60, "few"),
            (61, "one"),
            (62, "two"),
            (71, "one"),
            (72, "two"),
            (80, "few")
        ]
        for tag in ["gv"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup36() {
        let cases: [(Double, String)] = [
            (0, "zero"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (100, "other"),
            (1000, "two"),
            (1000.1, "other"),
            (10000, "two"),
            (100000, "two"),
            (1000000, "other"),
            (1001, "many"),
            (1003, "few"),
            (1004, "other"),
            (101, "many"),
            (102, "two"),
            (103, "few"),
            (121, "many"),
            (122, "two"),
            (123, "few"),
            (141, "many"),
            (142, "two"),
            (143, "few"),
            (161, "many"),
            (19, "other"),
            (2, "two"),
            (21, "many"),
            (22, "two"),
            (23, "few"),
            (3, "few"),
            (4, "other"),
            (41, "many"),
            (42, "two"),
            (43, "few"),
            (61, "many"),
            (62, "two"),
            (63, "few"),
            (81, "many"),
            (82, "two"),
            (83, "few")
        ]
        for tag in ["kw"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup37() {
        let cases: [(Double, String)] = [
            (0, "zero"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (10, "few"),
            (10.1, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (1003, "few"),
            (1011, "many"),
            (102, "other"),
            (103, "few"),
            (11, "many"),
            (110, "few"),
            (111, "many"),
            (2, "two"),
            (200, "other"),
            (202, "other"),
            (26, "many"),
            (3, "few"),
            (300, "other"),
            (302, "other"),
            (400, "other"),
            (402, "other"),
            (500, "other"),
            (502, "other"),
            (600, "other")
        ]
        for tag in ["ar", "ars"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。
    func testGroup38() {
        let cases: [(Double, String)] = [
            (0, "zero"),
            (0.1, "other"),
            (0.9, "other"),
            (1, "one"),
            (1.1, "other"),
            (1.7, "other"),
            (100, "other"),
            (1000, "other"),
            (10000, "other"),
            (100000, "other"),
            (1000000, "other"),
            (2, "two"),
            (20, "other"),
            (3, "few"),
            (4, "other"),
            (5, "other"),
            (6, "many"),
            (7, "other")
        ]
        for tag in ["cy"] {
            for (value, expected) in cases {
                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\(tag): \(value)")
            }
        }
    }
}
