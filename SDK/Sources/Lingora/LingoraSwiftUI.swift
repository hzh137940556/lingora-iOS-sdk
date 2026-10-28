// 提供随 SDK 更新事件刷新的 SwiftUI 文本组件。
import Combine
import Foundation
import SwiftUI

/// 将 Lingora 更新流桥接为 SwiftUI ObservableObject。
@MainActor
public final class LingoraSwiftUIUpdater: ObservableObject {
    private static weak var sharedInstance: LingoraSwiftUIUpdater?

    /// 活跃的默认文本共享观察对象；最后一个视图释放后仍可取消监听和加载。
    static func shared(lingora: Lingora = .shared) -> LingoraSwiftUIUpdater {
        if let sharedInstance, sharedInstance.lingora === lingora {
            // 新消费者必须重新尝试按需加载；SDK 统一合并请求和执行失败冷却。
            sharedInstance.requestPreload()
            return sharedInstance
        }
        let updater = LingoraSwiftUIUpdater(lingora: lingora)
        sharedInstance = updater
        return updater
    }

    private let lingora: Lingora
    private var task: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// 对齐 Android tFlow：先显示已有值，再按需预加载；语言切换时重复此过程。
    public init(lingora: Lingora = .shared) {
        self.lingora = lingora
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let updates = lingora.onTranslationsUpdated()
            self?.requestPreload()
            for await _ in updates {
                guard !Task.isCancelled else { return }
                self?.objectWillChange.send()
                self?.requestPreload()
            }
        }
    }

    /// 加载与更新监听独立执行，缓存和语言变化事件不等待网络完成。
    private func requestPreload() {
        let lingora = self.lingora
        loadTask?.cancel()
        loadTask = Task { await lingora.preload() }
    }

    deinit {
        task?.cancel()
        loadTask?.cancel()
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
        _updater = StateObject(wrappedValue: LingoraSwiftUIUpdater.shared())
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
    }
}
