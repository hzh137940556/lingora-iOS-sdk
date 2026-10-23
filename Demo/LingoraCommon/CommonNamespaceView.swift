// 提供可由主 App 引用的独立 common namespace SwiftUI 示例。
import Foundation
import Lingora
import SwiftUI

/// 定位 LingoraCommon framework 自己的本地化资源 Bundle。
private final class CommonBundleToken: NSObject {}

/// 展示 framework 内普通字符串和 plural 的远端翻译与 Bundle fallback。
@MainActor
public struct CommonNamespaceView: View {
    @StateObject private var updater = LingoraSwiftUIUpdater()

    private let language: String

    /// 创建跟随主 App 当前语言的 common namespace 视图。
    public init(language: String) {
        self.language = language
    }

    public var body: some View {
        _ = updater
        return VStack(alignment: .leading, spacing: 8) {
            Text(translated("common_title"))
                .font(.headline)
            Text(translated("welcome"))
            Text(translated("items_count", Int64(3)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 从 common table 读取普通字符串，并使用 framework Bundle 回退。
    private func translated(_ key: String) -> String {
        Lingora.shared.translate(
            key,
            table: "common",
            bundle: Bundle(for: CommonBundleToken.self),
            locale: Locale(identifier: language)
        )
    }

    /// 从 common table 读取带格式化参数的 plural。
    private func translated(_ key: String, _ argument: CVarArg) -> String {
        Lingora.shared.translate(
            key,
            argument,
            table: "common",
            bundle: Bundle(for: CommonBundleToken.self),
            locale: Locale(identifier: language)
        )
    }
}
