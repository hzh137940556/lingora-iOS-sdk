// 提供默认关闭的 Bundle.localizedString 普通文本兼容接管。
import Foundation

#if canImport(ObjectiveC)
import ObjectiveC

/// 进程内只执行一次 Bundle 方法交换。
@MainActor
enum BundleSwizzler {
    private(set) static var isEnabled = false

    /// 启用普通文本查找接管；后台线程继续使用系统原实现。
    static func enable() {
        guard !isEnabled,
              let original = class_getInstanceMethod(
                  Bundle.self,
                  #selector(Bundle.localizedString(forKey:value:table:))
              ),
              let replacement = class_getInstanceMethod(
                  Bundle.self,
                  #selector(Bundle.lingoraLocalizedString(forKey:value:table:))
              )
        else { return }
        method_exchangeImplementations(original, replacement)
        isEnabled = true
    }
}

private extension Bundle {
    /// 调用交换后的系统实现，再仅用远端普通文本覆盖。
    @objc dynamic func lingoraLocalizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        let fallback = lingoraLocalizedString(forKey: key, value: value, table: tableName)
        guard Thread.isMainThread else { return fallback }
        return MainActor.assumeIsolated {
            Lingora.shared.swizzledTranslation(for: key, table: tableName, bundle: self) ?? fallback
        }
    }
}
#else
/// 在无 Objective-C runtime 的宿主上保持兼容空实现。
@MainActor
enum BundleSwizzler {
    static var isEnabled: Bool { false }

    /// 无 Objective-C runtime 时不执行全局方法交换。
    static func enable() {}
}
#endif
