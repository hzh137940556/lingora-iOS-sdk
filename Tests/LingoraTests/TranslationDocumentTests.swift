// 验证 APPLE_SDK 文档结构、大小上限和常用 plural 规则。
import Foundation
import XCTest
@testable import Lingora

/// 覆盖不依赖网络的语言包行为。
final class TranslationDocumentTests: XCTestCase {
    /// 普通文本和 plural 必须按 locale 选择正确模板。
    func testParsesTextAndPluralRules() throws {
        let data = Data(
            #"{"welcome":"Hello %@","items":{"variations":{"plural":{"one":"%lld item","few":"%lld items few","many":"%lld items many","other":"%lld items"}}}}"#.utf8
        )
        let document = try TranslationDocument(data: data)
        XCTAssertEqual(
            document.template(
                for: "welcome",
                locale: Locale(identifier: "en"),
                arguments: ["Lingora"]
            ),
            "Hello %@"
        )
        XCTAssertEqual(
            document.template(
                for: "items",
                locale: Locale(identifier: "ru"),
                arguments: [Int64(2)]
            ),
            "%lld items few"
        )
        XCTAssertEqual(
            document.template(
                for: "items",
                locale: Locale(identifier: "pl"),
                arguments: [Int64(12)]
            ),
            "%lld items many"
        )
        XCTAssertEqual(
            PluralRules.category(for: 0, locale: Locale(identifier: "ar")),
            "zero"
        )
        XCTAssertEqual(
            PluralRules.category(for: 3, locale: Locale(identifier: "cs")),
            "few"
        )
        XCTAssertEqual(
            PluralRules.category(for: 7, locale: Locale(identifier: "ja")),
            "other"
        )
    }

    /// 缺少 other、未知 category 和超限响应必须整体拒绝。
    func testRejectsInvalidOrOversizedDocuments() {
        let invalid = Data(
            #"{"items":{"variations":{"plural":{"one":"one"}}}}"#.utf8
        )
        XCTAssertThrowsError(try TranslationDocument(data: invalid))
        XCTAssertThrowsError(
            try TranslationDocument(
                data: Data(repeating: 0, count: TranslationDocument.maximumBytes + 1)
            )
        )
    }

    /// 覆盖 Tolgee 对齐规则中的负数、小数和多 category 语言。
    func testCompletePluralRulesForNegativeAndFractionalValues() {
        let cases: [(String, Double, String)] = [
            ("en", -1, "other"),
            ("en", 1.5, "other"),
            ("cs", 2.1, "many"),
            ("hr", 1.2, "few"),
            ("sl", 1.5, "few"),
            ("lv", 0, "zero"),
            ("he", 2, "two"),
            ("ar", 3.5, "few"),
            ("ar", 11.5, "many"),
            ("cy", 6, "many"),
            ("ro", 1.5, "few"),
            ("br", 1_000_000, "many"),
            ("pa", 0.5, "one"),
            ("si", 0.1, "one"),
            ("ja", 1, "other"),
        ]

        for (language, value, expected) in cases {
            XCTAssertEqual(
                PluralRules.category(for: value, locale: Locale(identifier: language)),
                expected,
                "Unexpected category for \(language) value \(value)"
            )
        }
    }
}
