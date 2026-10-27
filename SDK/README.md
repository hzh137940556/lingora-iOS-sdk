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
上面的版本仅为格式示例，接入时选择仓库实际已发布的版本。

### 已有 Xcode iOS 工程

1. 打开自己的 `.xcodeproj` 或 `.xcworkspace`，在 Package Dependencies 中添加仓库 URL。
2. 验收时选择 Exact Version：正式版 `X.Y.Z`，开发版 `X.Y.Z-dev.N`；不要选开发分支，
   因为开发分支根目录包含整个仓库，Package 根实际位于 `SDK/`。
3. 将 `Lingora` product 关联到需要 `import Lingora` 的 target。App 与独立 framework 都使用时，
   分别关联，不复制 SDK 源码。资源仍由调用方 target 自己持有。
4. 保留 Xcode 生成的 `Package.resolved` 并提交到业务项目，以便 CI 复现版本。
5. 在主线程初始化，显式调用 `remoteFetch()`，界面使用 `LingoraText` 或更新流。

本地源码联调使用 Add Local Package，选择本仓库的 **`SDK/` 目录**，不是仓库根目录。
同一工程只保留一个 Lingora 来源；从本地转远端时移除本地引用，再添加远端并关联 product。
已有 `.strings` / `.stringsdict` 继续作为 fallback，CLI 不是 SDK 的运行时依赖。

### 已有 Swift Package

将以下配置合并到现有 manifest，不覆盖业务 targets。`YourFeature` 替换为实际使用 SDK 的 target：

```swift
let package = Package(
    name: "YourFeature",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(
            url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
            exact: "0.1.0" // 替换为已发布版本
        ),
    ],
    targets: [
        .target(
            name: "YourFeature",
            dependencies: [.product(name: "Lingora", package: "lingora-ios-sdk")]
        ),
    ]
)
```

本地改用 `.package(name: "Lingora", path: "../lingora-iOS-sdk/SDK")`，对应 product 的
`package:` 改为 `"Lingora"`。路径按消费工程所在位置调整，两种声明二选一。
Swift Package 自身携带资源时使用其 `Bundle.module` 传给 `translate` / `LingoraText`；
framework 则传自己的 Bundle，不能依赖 `.main` 找到其他模块的资源。

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
