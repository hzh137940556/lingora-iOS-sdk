# Lingora Swift Package

Lingora 的 iOS 运行时 SDK，负责读取 `APPLE_SDK` Content Delivery、缓存远端翻译，并在远端不可用时
回退到调用方 Bundle 的可选 `APPLE_SDK` JSON 或 `.strings` / `.stringsdict`。Package 只包含 `Lingora` library target 和
`LingoraTests` test target。

## 要求与安装

- iOS 16+
- Swift 6 / Xcode 16+
- macOS 13 仅作为 `swift build` / `swift test` 宿主

稳定版本：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    from: "0.1.0"
)
```

测试渠道使用精确预发布版本：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    exact: "0.1.0-dev.1"
)
```

Product 和 target 都叫 `Lingora`。版本 Tag 的根目录就是本 Package，不包含 Demo、CLI 或仓库脚本。

## 最小接入

Content Delivery 必须使用 Lingora 的 `APPLE_SDK` 格式。默认 table 路径为 `{language}.json`，
namespace 路径为 `{namespace}/{language}.json`。

```swift
import Lingora

Lingora.shared.initialize(
    contentDeliveryURL: URL(string: "https://cdn.example.com/apple")!,
    locale: .current,
    language: "en-US",
    namespaces: ["app", "common"]
)

await Lingora.shared.remoteFetch()

let title = Lingora.shared.translate("welcome", table: "app")
let greeting = Lingora.shared.translate("welcome_name", "Lingora", table: "app")
let items = Lingora.shared.translate("items_count", Int64(2), table: "app")
let sharedTitle = Lingora.shared.translate("welcome", table: "common")
```

SwiftUI 可直接使用响应式组件：

```swift
LingoraText("welcome", table: "app")
LingoraText("items_count", Int64(2), table: "app")
```

查找顺序为远端内存文档、磁盘缓存、可选 Bundle JSON、调用方 Bundle 的 `.strings/.stringsdict`、Key。
`setCustomLocale(_:language:)` 切换语言后需调用 `remoteFetch()`；传入其他 language 的
`remoteFetch(language:)` 只预取缓存，不切换当前语言。

`isInitialized`、`lastFetchDate` 和 `lastFetchSource` 可用于展示初始化与 Network/Cache 状态。
`enableSwizzling` 默认 `false`；启用后只覆盖主线程中的普通 `Bundle.localizedString`，plural 和后台线程
继续使用系统实现。新代码优先使用 `translate` 或 `LingoraText`。

## 可选的离线 APPLE_SDK JSON

当服务端原生 Apple 导出不能正确转换 ICU 占位符时，可以使用现有 CLI 的 `apple-sdk`
导出格式，无需升级 CLI 或修改服务端。将下载的目录以保留层级的方式复制进调用方 Bundle：

```text
Lingora/app/ja.json
Lingora/app/zh-CN.json
Lingora/common/ja.json
```

CLI 的 `pull.format` 设为 `apple-sdk`，`pull.fileStructureTemplate` 设为
`{namespace}/{languageTag}.{extension}`。这些配置属于消费工程，不由 SDK 读取。
Xcode 使用 folder reference 或保留目录的 Copy Files；Swift Package 使用 `.copy("Lingora")`。
不要将 JSON 文件平铺进 Bundle 根目录，也不要把 API Key 打包进 App。

在 `initialize` 中显式传入 `bundledTranslationsDirectory: "Lingora"` 启用；默认 `nil`
保持已有行为。目录名仅允许单个安全路径组件。无 namespace 的默认 table 对应
`Lingora/{languageTag}.json`；具名 table 对应 `Lingora/{namespace}/{languageTag}.json`。
framework 或资源 Package 调用 `translate` / `LingoraText` 时仍须传入自身 Bundle。

启用后查找顺序：远端内存/已恢复缓存 → Bundle JSON → 原生 `.strings/.stringsdict` → Key。
JSON 按显式 language（未指定时使用 locale 标签）、父语言、Bundle development language
逐 Key 回退；格式、大小校验与远端文档相同，无效文件不阻止继续回退。
普通参数和复数复用 APPLE_SDK 格式化，无需再次解析 ICU 或猜测 `%` 转义。
平台源文本仍应使用正确的 ICU 格式；本功能不改变上传转换行为。

本地 JSON 不需要 `remoteFetch` 就能使用，不改变 `lastFetchSource` 或写入网络缓存。
Bundle 是不可变资源，SDK 按 Bundle 路径缓存解析及缺失结果，`clearCache` 仅清理远端缓存。
可选 swizzling 继续只接管远端普通字符串；Bundle JSON 使用显式 SDK API，
不会改变 `NSLocalizedString` 或系统 plural 的行为。

## 运行时可靠性与状态

`remoteFetch()` 保持每次主动检查远端的行为。自动或重复触发的调用可以使用
`remoteFetch(forceRefresh: false)`：同一 language/table 请求失败后冷却 2 秒，再次调用使用当前
有效磁盘缓存或 Bundle 回退；默认调用或 `forceRefresh: true` 可立即重试。
不同 namespace 独立冷却，取消不会记作失败。

同一 URL 的请求与磁盘写入按顺序执行，不同 namespace 仍可并行；最新一次当前语言刷新
决定内存和状态，语言切换前的旧请求不会覆盖新语言。排队请求取消后不会发出网络请求，
但其等待结束时间受前一个请求的完成/超时限制。

`loadState` 与 `onLoadStateChanged()` 提供当前语言的状态：`idle`、`loading`、
`loaded(source:failedTables:)`、`fallback(failedTables:)` 和 `cancelled`。
订阅立即得到当前值。`failedTables` 的空字符串代表根文档；部分 namespace 失败时仍保留
有效翻译。`fallback` 表示本次请求没有取得有效文档，不表示已清空以前的内存翻译。
预取其他语言不修改当前语言的状态；详细原因继续通过不含响应正文的日志提供。

外部 JSON 的 printf 模板在格式化前检查所需参数数量、位置和 ABI 类型，允许译文不使用额外参数。支持对象、常用整数、
浮点、显式位置、固定宽度/精度和百分号；拒绝 `%n`、指针、C 字符串、动态宽度、混合位置
及超大宽度。检查失败继续回退到本地资源；无参数调用保持原文。原生 `.stringsdict`
仍由 Foundation 处理，调用方须按自己的原生资源签名传参。
极大或非有限 plural 数值安全选择 `other`，不执行溢出的整数转换。

`setCustomLocale` 不再要求语言存在于 `Bundle.main` 的 lproj 中；JSON-only、framework 和远端
语言均可按安全语言标签选择。该方法不声明语言已发布，也不自动发现可用语言或发起网络请求；
缺失内容继续遵循回退顺序，manifest/语言目录协议保持不变。
