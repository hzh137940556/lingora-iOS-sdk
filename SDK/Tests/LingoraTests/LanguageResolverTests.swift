// 使用 Android 相同的候选标签案例验证语言匹配。
import XCTest
@testable import Lingora

/// 避免引入 Android 没有的跨地区选择和文字系统推断。
final class LanguageResolverTests: XCTestCase {
    /// 有目录时按候选标签匹配，无目录则精确请求；默认语言无需存在于目录中。
    func testAndroidMatchingOrder() {
        XCTAssertEqual(LanguageResolver.resolve("zh-Hant-TW", available: ["zh", "zh-TW", "zh-Hant"], defaultLanguage: nil), "zh-Hant")
        XCTAssertEqual(LanguageResolver.resolve("zh-TW", available: ["zh-Hant", "zh"], defaultLanguage: nil), "zh")
        XCTAssertEqual(LanguageResolver.resolve("en-AU", available: ["en-US", "en", "en-GB"], defaultLanguage: nil), "en")
        XCTAssertNil(LanguageResolver.resolve("en-AU", available: ["en-US", "en-GB"], defaultLanguage: nil))
        XCTAssertEqual(LanguageResolver.resolve("EN-us", available: ["en-US", "en"], defaultLanguage: nil), "en-US")
        XCTAssertEqual(LanguageResolver.resolve("fr-CA", available: nil, defaultLanguage: "en"), "fr-CA")
        XCTAssertEqual(LanguageResolver.resolve("fr-CA", available: [], defaultLanguage: "en"), "en")
        XCTAssertEqual(LanguageResolver.resolve("fr-CA", available: ["ja"], defaultLanguage: "en-US"), "en-US")
        XCTAssertEqual(LanguageResolver.resolve("sr-Latn-RS-REVISED", available: ["sr-RS-REVISED", "sr"], defaultLanguage: nil), "sr-RS-REVISED")
        XCTAssertNil(LanguageResolver.resolve("sr-Latn", available: ["sr-Cyrl"], defaultLanguage: nil))
    }

    /// 静态目录拒绝路径和重复标签，空数组与未知目录 nil 明确区分。
    func testListValidation() {
        XCTAssertTrue(LanguageResolver.validList([]))
        XCTAssertTrue(LanguageResolver.validList(["en-US", "zh-CN"]))
        XCTAssertFalse(LanguageResolver.validList(["en", "EN"]))
        XCTAssertFalse(LanguageResolver.validList(["../en"]))
    }
}
