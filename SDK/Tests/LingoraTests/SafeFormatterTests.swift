// 验证外部模板的 ABI 安全检查、格式能力和复数数值边界。
import Foundation
import XCTest
@testable import Lingora

/// 使用真实 printf 输出覆盖有效模板，并确认危险模板不会进入 C 格式化。
final class SafeFormatterTests: XCTestCase {
    /// 支持对象、位置参数、数字宽度、小数和百分号，保持无参数原文。
    func testSupportedFormats() {
        let locale = Locale(identifier: "en-US")
        XCTAssertEqual(SafeFormatter.render("Hello %@", arguments: ["iOS"], locale: locale), "Hello iOS")
        XCTAssertEqual(SafeFormatter.render("%2$@ %1$lld", arguments: [Int64(3), "items"], locale: locale), "items 3")
        XCTAssertEqual(SafeFormatter.render("%1$@ %1$@", arguments: ["x"], locale: locale), "x x")
        XCTAssertEqual(SafeFormatter.render("%04d %.1f %%", arguments: [Int32(3), 1.5], locale: locale), String(format: "%04d %.1f %%", locale: locale, arguments: [Int32(3), 1.5]))
        XCTAssertEqual(SafeFormatter.render("100% complete", arguments: [], locale: locale), "100% complete")
        XCTAssertEqual(SafeFormatter.render("%@", arguments: [NSNumber(value: 3)], locale: locale), "3")
        XCTAssertEqual(SafeFormatter.render("one item", arguments: [Int64(1)], locale: locale), "one item")
        XCTAssertEqual(SafeFormatter.render("%@", arguments: ["used", "unused"], locale: locale), "used")
    }

    /// 拒绝参数数量、类型、索引、指针、混用位置和超大宽度，避免越界读取或分配。
    func testRejectsUnsafeFormats() {
        let cases: [(String, [CVarArg])] = [
            ("%@ %@", ["one"]), ("%@", [Int64(1)]), ("%lld", ["text"]),
            ("%f", [Int64(1)]), ("%2$@", ["one"]), ("%2$@", [1.5, "two"]), ("%0$@", ["one"]),
            ("%#@count@", ["value"]), ("%n", [Int64(0)]), ("%s", ["text"]), ("%p", [Int64(0)]),
            ("%*d", [Int32(2), Int32(3)]), ("%1$@ %@", ["a", "b"]),
            ("%999999999@", ["a"]), ("%@ trailing %", ["a"]),
            ("%d", [Int.max]), ("%L@", ["a"]),
        ]
        for (template, arguments) in cases {
            XCTAssertNil(SafeFormatter.render(template, arguments: arguments, locale: Locale(identifier: "en")), template)
        }
    }

    /// 极大整数、无穷和 NaN 必须安全选择 other，不触发 Double 到 Int 陷阱。
    func testPluralNumericBoundaries() throws {
        let values = [Double(Int64.max), Double(UInt64.max), Double.greatestFiniteMagnitude,
                      Double.infinity, -Double.infinity, Double.nan, -1]
        for number in values {
            XCTAssertEqual(PluralRules.category(for: number, locale: Locale(identifier: "en")), "other")
        }
        let document = try TranslationDocument(data: Data(#"{"items":{"variations":{"plural":{"other":"%lld items"}}}}"#.utf8))
        XCTAssertEqual(document.template(for: "items", locale: Locale(identifier: "en"), arguments: [Int64.max]), "%lld items")
    }
}
