// 使用实际 App/framework 产物和已发布 SDK 验证离线 JSON，不调用网络获取。
import Foundation
import Lingora

/// 对照产物中的 JSON 检查公开 API 返回值及参数、复数格式化。
@main
struct BundledProbe {
    /// 从两个真实 Bundle 读取下载的目标语言，并确认未依赖远端缓存。
    @MainActor
    static func main() throws {
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let app = Bundle(url: appURL)!
        let common = Bundle(url: appURL.appendingPathComponent("Frameworks/LingoraCommon.framework"))!
        let sdk = Lingora.shared
        sdk.initialize(contentDeliveryURL: URL(string: "https://bundled-probe.invalid")!,
                       language: "ja", namespaces: ["app", "common"],
                       bundledTranslationsDirectory: "Lingora")
        for language in ["ja", "zh-CN"] {
            try sdk.setCustomLocale(Locale(identifier: language), language: language)
            for (namespace, bundle) in [("app", app), ("common", common)] {
                let url = bundle.resourceURL!.appendingPathComponent("Lingora/\(namespace)/\(language).json")
                let data = try Data(contentsOf: url)
                let values = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let welcome = values["welcome"] as! String
                precondition(sdk.translate("welcome", table: namespace, bundle: bundle) == welcome)
                let plural = values["items_count"] as! [String: Any]
                let forms = (plural["variations"] as! [String: Any])["plural"] as! [String: String]
                let locale = Locale(identifier: language)
                let expected = String(format: forms["other"]!, locale: locale, arguments: [Int64(3)])
                precondition(expected.contains("3") && !expected.contains("%"))
                precondition(sdk.translate("items_count", Int64(3), table: namespace, bundle: bundle) == expected)
                if namespace == "app" {
                    let formatted = sdk.translate("welcome_name", "iOS", table: namespace, bundle: bundle)
                    precondition(formatted.contains("iOS") && !formatted.contains("%@"))
                }
                print("Verified bundled offline \(namespace)/\(language): \(welcome); \(expected)")
            }
        }
        precondition(sdk.lastFetchSource == nil && sdk.lastFetchDate == nil)
    }
}
