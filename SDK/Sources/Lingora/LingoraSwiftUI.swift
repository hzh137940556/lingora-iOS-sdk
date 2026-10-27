// 提供随 SDK 更新事件刷新的 SwiftUI 文本组件。
import Combine
import Foundation
import SwiftUI

/// 将 Lingora 更新流桥接为 SwiftUI ObservableObject。
@MainActor
public final class LingoraSwiftUIUpdater: ObservableObject {
    private var task: Task<Void, Never>?

    /// 对齐 Android tFlow：先显示已有值，再按需预加载；语言切换时重复此过程。
    public init(lingora: Lingora = .shared) {
        task = Task { [weak self] in
            let updates = lingora.onTranslationsUpdated()
            await lingora.preload()
            for await _ in updates {
                guard !Task.isCancelled else { return }
                self?.objectWillChange.send()
                await lingora.preload()
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

/// 显示远端优先、Bundle fallback 的响应式文本。
@MainActor
public struct LingoraText: View {
    private let key: String
    private let arguments: [CVarArg]
    private let table: String?
    private let bundle: Bundle
    private let locale: Locale
    @StateObject private var updater: LingoraSwiftUIUpdater

    /// 创建随语言包更新自动刷新的文本。
    public init(
        _ key: String,
        _ arguments: CVarArg...,
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) {
        self.key = key
        self.arguments = arguments
        self.table = table
        self.bundle = bundle
        self.locale = locale
        _updater = StateObject(wrappedValue: LingoraSwiftUIUpdater())
    }

    public var body: some View {
        Text(
            Lingora.shared.translateValue(
                key,
                arguments: arguments,
                table: table,
                bundle: bundle,
                locale: locale
            )
        )
        .id(ObjectIdentifier(updater))
    }
}
