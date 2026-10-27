# Lingora Swift Package

Lingora 的 iOS 运行时 SDK，负责读取 `APPLE_SDK` Content Delivery、缓存远端翻译，并在远端不可用时
回退到调用方 Bundle 的 `.strings` / `.stringsdict`。Package 只包含 `Lingora` library target 和
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

查找顺序为远端内存文档、磁盘缓存、调用方 Bundle 的 `.strings/.stringsdict`、Key。
`setCustomLocale(_:language:)` 切换语言后需调用 `remoteFetch()`；传入其他 language 的
`remoteFetch(language:)` 只预取缓存，不切换当前语言。

`isInitialized`、`lastFetchDate` 和 `lastFetchSource` 可用于展示初始化与 Network/Cache 状态。
`enableSwizzling` 默认 `false`；启用后只覆盖主线程中的普通 `Bundle.localizedString`，plural 和后台线程
继续使用系统实现。新代码优先使用 `translate` 或 `LingoraText`。
