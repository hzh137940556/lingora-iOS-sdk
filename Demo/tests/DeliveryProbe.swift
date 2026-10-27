// 使用真实发布 SDK 检查远程 namespace、语言切换、参数替换和复数；消费者不含 fallback 资源。
import Foundation
import Lingora

@main
struct DeliveryProbe {
    /// 独立下载当前文档作对照，再验证 SDK 的公开翻译结果。
    @MainActor
    static func main() async throws {
        let baseURL = URL(string: CommandLine.arguments[1])!
        let sdk = Lingora.shared
        sdk.initialize(contentDeliveryURL: baseURL, language: "en-US", namespaces: ["app", "common"])
        for language in ["en-US", "ja", "zh-CN"] {
            try sdk.setCustomLocale(Locale(identifier: language), language: language)
            await sdk.remoteFetch()
            precondition(sdk.lastFetchDate != nil, "SDK did not load CDN")
            for namespace in ["app", "common"] {
                let url = baseURL.appendingPathComponent(namespace).appendingPathComponent(language + ".json")
                let (data, response) = try await URLSession.shared.data(from: url)
                precondition((response as? HTTPURLResponse)?.statusCode == 200)
                let values = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let welcome = values["welcome"] as! String
                precondition(sdk.translate("welcome", table: namespace) == welcome)
                let plural = values["items_count"] as! [String: Any]
                let variations = plural["variations"] as! [String: Any]
                let forms = variations["plural"] as! [String: String]
                let expected = String(format: forms["other"]!, locale: Locale(identifier: language), arguments: [Int64(3)])
                precondition(expected.contains("3") && !expected.contains("%"), "Invalid plural placeholder")
                precondition(sdk.translate("items_count", Int64(3), table: namespace, locale: Locale(identifier: language)) == expected)
                if namespace == "app" {
                    let formatted = sdk.translate("welcome_name", "iOS", table: namespace)
                    precondition(formatted.contains("iOS") && !formatted.contains("%@"), "Invalid string placeholder")
                }
                print("Verified \(namespace)/\(language): \(welcome); plural=\(expected)")
            }
        }
        print("Published SDK loaded all six CDN documents and formatted translations successfully")
    }
}
