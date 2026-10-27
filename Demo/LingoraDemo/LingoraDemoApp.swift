// 启动 SwiftUI Demo，并仅通过 Lingora 的公开 API 配置 SDK。
import Lingora
import SwiftUI

/// 提供独立的 Demo App 入口。
@main
struct LingoraDemoApp: App {
    /// 读取构建时注入的公开地址；未配置时保留 Bundle fallback。
    init() {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "LingoraContentDeliveryURL"
        ) as? String,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let url = URL(string: value) else { return }
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
