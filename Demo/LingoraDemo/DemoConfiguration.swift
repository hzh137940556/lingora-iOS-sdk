// 读取 Demo 自有运行配置，不让 SDK 依赖 App 环境。
import Foundation

/// 提供 Content Delivery URL 的环境覆盖和 Info.plist 回退。
enum DemoConfiguration {
    /// 按进程环境、Info.plist 顺序读取公开 URL。
    static var contentDeliveryURL: URL? {
        let environment = ProcessInfo.processInfo.environment[
            "LINGORA_CONTENT_DELIVERY_URL"
        ]
        let plist = Bundle.main.object(
            forInfoDictionaryKey: "LINGORA_CONTENT_DELIVERY_URL"
        ) as? String
        return [environment, plist]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            .flatMap(URL.init(string:))
    }
}
