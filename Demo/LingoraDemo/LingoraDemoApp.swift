// 启动 SwiftUI Demo，并仅通过 Lingora 的公开 API 配置 SDK。
import Lingora
import SwiftUI

/// 提供独立的 Demo App 入口。
@main
struct LingoraDemoApp: App {
    /// 初始化可选 Content Delivery；未配置时保留 Bundle fallback。
    init() {
        if let url = DemoConfiguration.contentDeliveryURL {
            Lingora.shared.initialize(
                contentDeliveryURL: url,
                locale: Locale(identifier: "en-US"),
                language: "en-US",
                namespaces: ["app", "common"],
                enableDebugLogs: true
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
