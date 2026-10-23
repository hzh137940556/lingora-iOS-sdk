// 启动 SwiftUI Demo，并仅通过 Lingora 的公开 API 配置 SDK。
import Lingora
import SwiftUI

/// 提供独立的 Demo App 入口。
@main
struct LingoraDemoApp: App {
    /// 使用 Demo 的公开 Content Delivery URL 初始化 SDK。
    init() {
        guard let url = URL(
            string: "https://cosly-dev.s3.us-west-2.amazonaws.com/lingora/localstrings/ios/v1"
        ) else { return }
        Lingora.shared.initialize(
            contentDeliveryURL: url,
            locale: Locale(identifier: "en-US"),
            language: "en-US",
            namespaces: ["app", "common"],
            enableDebugLogs: true
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
