# Lingora iOS SDK

Lingora 的 Swift Package。SDK 负责读取 `APPLE_SDK` Content Delivery、缓存和 Bundle fallback；
`Demo/` 是独立 SwiftUI App，只通过公开 `Lingora` product 使用 SDK。

```text
Package.swift                 Swift Package 入口
Sources/Lingora/              独立 SDK target：Lingora
Tests/LingoraTests/           独立 test target：LingoraTests
Demo/LingoraDemo.xcodeproj/   独立 Xcode App target：LingoraDemo
```

`LingoraDemo` 使用仓库根目录的 local package reference，只链接公开 library product `Lingora`。
Demo 不属于 `Package.swift`，SDK target 也不引用 Demo、CLI 或 App 环境配置。

## 要求与安装

- iOS 16+
- Swift 6 / Xcode 16+
- macOS 13 仅用于 `swift build` / `swift test` 宿主验证，不作为正式客户端平台承诺

稳定版本发布后，在 Xcode 中添加仓库 URL并选择 SemVer 版本，或在 `Package.swift` 中使用：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    from: "0.1.0"
)
```

Product 和 target 都叫 `Lingora`。Package 不包含 Demo、CLI 或 App 环境配置。

测试渠道使用 SwiftPM 可识别的预发布 SemVer，可固定到精确版本：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    exact: "0.1.0-dev.1"
)
```

## 最小接入

Content Delivery 必须使用 Lingora 的 `APPLE_SDK` 格式。默认 table 的路径是
`{language}.json`，namespace 对应 `{namespace}/{language}.json`。

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

`enableSwizzling` 默认 `false`。启用后只覆盖主线程中的普通 `Bundle.localizedString`；
plural 和后台线程继续使用系统实现。新代码优先使用 `translate` 或 `LingoraText`。

## Demo 配置

Demo 使用开发项目 `6acbf9e2-b605-40e4-90b1-066fbb1d4506`、`develop` 分支、`app` 与
`common` namespace、`en-US` 基础语言以及 `ja` / `zh-CN` 目标语言。

复制本机配置并填写公开 Content Delivery URL：

```bash
cp Demo/Config/Local.xcconfig.example Demo/Config/Local.xcconfig
open Demo/LingoraDemo.xcodeproj
```

运行时 `LINGORA_CONTENT_DELIVERY_URL` 环境变量优先于 Info.plist 中由 xcconfig 注入的值；
两者都没有时 Demo 只展示 Bundle fallback。URL 不属于 SDK Package 配置。

Apple CLI 配置位于 `Demo/ci/lingora.dev.json`，基础文件包含 `app`、`common` 两组
`.strings + .stringsdict`，pull 输出到忽略提交的 `Demo/LingoraDemo/Generated/`。普通 Xcode
build 不会执行 CLI；生成目录使用合并安装以保留受 Git 管理的 `.gitignore`。获得明确远端写入授权
并设置 `LINGORA_API_KEY` 后，才可运行：

```bash
make -C Demo mock_ci
```

`Demo/lingora-cli.version` 固定为已从 PyPI 安装验收、支持 Apple 多 namespace 的
`0.1.0rc3`。本地 `cli-validate` 不访问真实项目；push/pull 和 Content Delivery 仍需在获得授权后验收。

## 验证与发布

```bash
make sdk-build
make sdk-test
make demo-build
make check-boundaries
make release-test
make verify
```

PR、`develop` 和 `main` 都运行 `iOS SDK CI`。SwiftPM 不上传 Maven 式二进制包；仓库 URL
加 SemVer Tag 就是可消费版本，因此发布工作流会先验证 SDK、Demo、来源分支和审批环境，审批通过后
才创建不可移动的 Tag 与 GitHub Release：

| 渠道 | 来源 | 版本/Tag | GitHub Environment |
| --- | --- | --- | --- |
| dev | `develop` | `X.Y.Z-dev.N` | `ios-sdk-dev` |
| release | `main` | `X.Y.Z` | `ios-sdk-release` |

代码合并且分支同步后，由维护者运行：

```bash
# develop：请求预发布版本；不会在本机直接创建 Tag
make publish-dev VERSION=0.1.0-dev.1

# main：请求稳定版本
make publish VERSION=0.1.0
```

两个命令先运行完整 `make verify`，再通过 `gh workflow run` 请求 Actions；只有 publish Job
拥有 `contents: write`。版本一经创建不得移动或覆盖，修复必须递增版本。首次启用前需按
[GitHub 配置清单](GITHUB_SETUP.md)设置分支保护、Tag ruleset 和两个审批环境。
