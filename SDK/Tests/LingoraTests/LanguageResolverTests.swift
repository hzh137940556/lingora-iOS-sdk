// 验证目录校验与保守的地区、文字系统匹配。
import Foundation
import XCTest
@testable import Lingora

/// 验证语言选择及目录输入的确定性边界。
final class LanguageResolverTests: XCTestCase {
    /// 精确命中优先，不按数组顺序随机选择，也不跨简繁文字系统。
    func testMatching() {
        XCTAssertEqual(LanguageResolver.resolve("zh-TW", available: ["zh-CN", "zh-Hant", "en-US"], defaultLanguage: "en-US"), "zh-Hant")
        XCTAssertEqual(LanguageResolver.resolve("zh-HK", available: ["zh-CN", "en-US"], defaultLanguage: "en-US"), "en-US")
        XCTAssertEqual(LanguageResolver.resolve("en-AU", available: ["en-US", "en", "en-GB"], defaultLanguage: nil), "en")
        XCTAssertEqual(LanguageResolver.resolve("en-AU", available: ["en-US", "en-GB"], defaultLanguage: nil), "en-GB")
        XCTAssertEqual(LanguageResolver.resolve("EN-us", available: ["en-US", "en"], defaultLanguage: nil), "en-US")
        XCTAssertEqual(LanguageResolver.resolve("fr-CA", available: ["ja"], defaultLanguage: nil), "fr-CA")
        XCTAssertEqual(LanguageResolver.resolve("fr-CA", available: [], defaultLanguage: "en"), "fr-CA")
        XCTAssertEqual(LanguageResolver.resolve("sr-Latn", available: ["sr-Cyrl"], defaultLanguage: nil), "sr-Latn")
    }

    /// 目录不能带路径、重复标签或超大输入，允许空目录保持精确请求。
    func testManifestValidation() throws {
        XCTAssertEqual(try LanguageManifest(data: Data(#"{"locales":["en-US","zh-CN"]}"#.utf8)).locales, ["en-US", "zh-CN"])
        for json in [#"{"locales":["en","EN"]}"#, #"{"locales":["../en"]}"#, #"{"locales":[1]}"#, #"{}"#] {
            XCTAssertThrowsError(try LanguageManifest(data: Data(json.utf8)))
        }
        XCTAssertThrowsError(try LanguageManifest(data: Data(repeating: 32, count: 256 * 1024 + 1)))
    }
}
