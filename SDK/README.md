# Lingora Swift Package

Lingora 的 iOS 运行时 SDK，负责读取 `APPLE_SDK` Content Delivery、缓存远端翻译，并在远端不可用时
回退到调用方 Bundle 的可选 `APPLE_SDK` JSON 或 `.strings` / `.stringsdict`。Package 只包含 `Lingora` library target 和
`LingoraTests` test target。

## 要求与安装

- iOS 16+
- Swift 6 / Xcode 16+
- macOS 13 仅作为 `swift build` / `swift test` 宿主

当前可用的预发布版本（精确锁定）：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    exact: "0.1.0-dev.3"
)
```

目前没有发布稳定版 `0.1.0`，不要使用它作为安装版本。Product 和 target 都叫 `Lingora`。
版本 Tag 的根目录就是本 Package，不包含 Demo、CLI 或仓库脚本。

### 已有 Xcode iOS 工程

1. 打开自己的 `.xcodeproj` 或 `.xcworkspace`，在 Package Dependencies 中添加仓库 URL。
2. 验收时选择 Exact Version：正式版 `X.Y.Z`，开发版 `X.Y.Z-dev.N`；不要选开发分支，
   因为开发分支根目录包含整个仓库，Package 根实际位于 `SDK/`。
3. 将 `Lingora` product 关联到需要 `import Lingora` 的 target。App 与独立 framework 都使用时，
   分别关联，不复制 SDK 源码。资源仍由调用方 target 自己持有。
4. 保留 Xcode 生成的 `Package.resolved` 并提交到业务项目，以便 CI 复现版本。
5. 在主线程初始化，SwiftUI 使用 `LingoraText` 自动加载；UIKit 使用下面的显式加载方式。

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
            exact: "0.1.0-dev.3"
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

只需添加 Package、在 App 启动时初始化一次、使用翻译组件。无需先配置 CLI 或 CI。
Content Delivery 使用 `APPLE_SDK` 格式，namespace 路径为 `{namespace}/{language}.json`。
以下 URL、语言列表和 namespace 替换为自己项目实际已发布的值：

```swift
import Lingora

// App 启动时，在主线程初始化一次。
Lingora.shared.initialize(
    contentDeliveryURL: URL(string: "https://cdn.example.com/apple")!,
    defaultNamespace: "app",
    availableLanguages: ["en-US", "ja", "zh-CN"],
    defaultLanguage: "en-US"
)

// SwiftUI body 中自动加载和响应语言变化，无需另行 remoteFetch。
LingoraText("welcome")
LingoraText("items_count", Int64(2))
```

`availableLanguages` 是自己发布的语言列表，按系统 locale 匹配；Apple Delivery 不提供 manifest。
如果产品只使用某个固定语言，可改传 `language: "en-US"`。不传 defaultNamespace 时继续读取
根目录 `{language}.json`，保持已有接入兼容性。额外 framework namespace 用 `namespaces: ["common"]`
注册，翻译时传 `table: "common"` 和该 framework 的 Bundle。

UIKit 或非响应式调用显式加载，随后更新自己的 UI：

```swift
await Lingora.shared.preload()
let title = Lingora.shared.translate("welcome")
let greeting = Lingora.shared.translate("welcome_name", "Lingora")
```

切换语言用 `setCustomLocale(_:language:)`。`LingoraText` 和 updater 自动按需加载；手动接入则再次
调用 `preload()` 并更新 UI，或订阅 `onTranslationsUpdated()`。`remoteFetch()` 用于主动检查译文更新；
传其他 language 的 `remoteFetch(language:)` 只预取缓存，不切换当前语言。

查找顺序为远端内存/已恢复磁盘缓存、可选 Bundle JSON、调用方 Bundle 的 `.strings/.stringsdict`、Key。
`isInitialized`、`lastFetchDate` 和 `lastFetchSource` 可用于检查初始化和加载状态。
`enableSwizzling` 默认关闭，新代码使用 `translate` 或 `LingoraText` 即可。

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
平台源文本仍应使用正确的 ICU 格式；运行时不修复上传数据。仓库 Demo 的 `push_icu.py` 提供保守的上传前转换。

本地 JSON 不需要 `remoteFetch` 就能使用，不改变 `lastFetchSource` 或写入网络缓存。
Bundle 是不可变资源，SDK 按 Bundle 路径缓存解析及缺失结果，`clearCache` 仅清理远端缓存。
可选 swizzling 继续只接管远端普通字符串；Bundle JSON 使用显式 SDK API，
不会改变 `NSLocalizedString` 或系统 plural 的行为。

## 运行时可靠性与状态

本节 API 已包含在 `0.1.0-dev.3`。

`remoteFetch()` 对应 Android `refresh()`，每次主动检查远端。`preload()` 对应 Android 的同名方法：
多个消费者共享一次加载，已加载的 namespace 不重复请求；失败冷却 5 秒，主动 remoteFetch 可立即重试。
内存文档及加载标记按实际语言＋namespace 隔离；自动匹配和显式请求不会互相误标已加载。
切回已加载语言可立即复用该语言的文档，未加载的 namespace 继续按需补齐；取消不会记作网络失败。
切走后完成的手动刷新只更新其对应语言缓存，不覆盖当前其他语言的展示。
磁盘恢复本身不标记已检查网络，首次 preload 仍检查远端。

对齐 Android 的 `loadMutex`，预加载和主动刷新按批次串行执行并提交结果，同一批次的不同
namespace 仍可并行。预加载取得执行权后重新检查缺失项，语言切换前的旧请求不会覆盖新语言。
排队请求取消后立即退出，不发出网络请求，也不修改正在执行的刷新状态。
SwiftUI 的更新监听与加载独立执行，恢复的缓存和语言变化通知不必等待网络完成。
`clearCache()` 清空所有语言的内存文档并使旧缓存代次及失败冷却失效；旧的在途、排队或延迟启动
请求不能重新写回磁盘。清理与原子写入共享同步屏障，清理后的新请求仍可正常缓存。
进行中的手动请求不必立即终止网络传输，但其结果不再应用或写入。

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


## 与 Android 对齐的接入方式

本节 API 已包含在 `0.1.0-dev.3`，Demo 固定消费该已发布版本。

```swift
Lingora.shared.initialize(
    contentDeliveryURL: deliveryURL,
    locale: .current,
    namespaces: ["common"],
    bundledTranslationsDirectory: "Lingora",
    defaultNamespace: "app",
    availableLanguages: ["en-US", "ja", "zh-CN"],
    defaultLanguage: "en-US"
)
await Lingora.shared.preload() // 类似 Android 页面启动时的 preload
// 刷新按钮继续调用 await Lingora.shared.remoteFetch()
```

- `defaultNamespace` 对应 Android 默认 namespace，自动加入加载集合；显式 table 优先。
  省略 table 时远端与 Bundle JSON 使用默认 namespace；原生 Bundle 仍使用原本的 table，nil 为 Localizable。
  为兼容已发布 iOS API，defaultNamespace 默认 nil，保持根文档路径；业务方通常显式配置 app。
- 语言匹配采用 Android 的候选顺序：完整标签 → language-script-region → language-script →
  language-region-variant → language-region → language → defaultLanguage。
  只使用标签显式携带的 script，不推断文字系统、不挑选其他地区。例如 en-AU 不自动选择 en-US，
  zh-TW 也不自动选择 zh-Hant；可以匹配列表中的基础语言 zh。默认语言与 Android 一样不要求位于目录中。
- **平台差异仅在语言目录来源**：Android 的 android-sdk Delivery 输出 manifest；Apple Delivery 不输出。
  iOS 用 `availableLanguages` 直接提供已发布列表，不下载 manifest，不提供自定义目录 URL/文件名。
  nil 表示目录未知，直接请求原语言；空列表或无匹配时使用 defaultLanguage，无默认语言则回退本地资源。
  显式 `language` 保留已发布 iOS API 的精确请求语义；预取不切换当前语言。
- Android 初始化和 setLocale 本身不发请求，iOS 同样如此（可异步恢复磁盘缓存）。
  `preload()` 合并并发消费者、只补缺少的 namespace；`remoteFetch()` 主动刷新。
  `LingoraText` / `LingoraSwiftUIUpdater` 与 Android tFlow 一样，在订阅及语言更新时按需 preload，
  先显示缓存/Bundle，再更新远端内容。普通同步 translate 不联网；没有响应式订阅时，由调用方显式 preload。
  没有额外的自动加载策略枚举或 forceRefresh 配置。切换语言/清缓存取消旧 preload，并阻止旧结果覆盖当前语言。

保留 iOS 的 Bundle、SwiftUI、系统 plural 回退及上传 ICU 转换，不要求 Android 改动。数组翻译按本轮范围暂不做。

## 当前源码中的修复（尚未发布）

安装示例仍指向已发布的 `0.1.0-dev.3`；以下变更需要后续 SDK 发版后才能通过远端版本使用。

- 复数规则来自固定 Unicode CLDR 49 cardinal 数据，覆盖地区特例，负数按绝对值计算。
  Double API 使用最短十进制表示，不保留可见尾零，不支持 compact notation；普通数值的 `e/c` 为 0。
  Android 使用系统 ICU，其 CLDR 版本随 OS 变化，因此规则版本可能不同。
- 下载过程中限制实际响应为 10 MiB，缺失或不可信 Content-Length 也受限；超限继续使用有效缓存。
- `initialize` 返回可忽略的 Bool：无效配置为 false，成功为 true；重复调用保留第一次配置并返回 true。
  既有直接调用不需要修改，也可以继续检查 `isInitialized`。
- 可选 swizzling 默认只允许 `Bundle.main`；需要兼容其他 Bundle 时传 `swizzlingBundles: [bundle]`。
  列表替换默认值，仅普通远端文本可覆盖，其他 Bundle、plural 和后台线程保持系统行为。
- 活跃的默认 `LingoraText` 共用一个更新观察对象，最后一个视图释放后取消监听与任务；
  手动创建的 `LingoraSwiftUIUpdater(lingora:)` 仍保持各自生命周期。

规则维护方式：开发仓库 `scripts/cldr/plurals.xml` 固定源数据，运行
`python3 scripts/generate_plural_rules.py` 更新规则和官方样例测试；`make sdk-test` 检查生成物一致性。
运行时不联网下载规则，也不依赖第三方库。许可见 THIRD_PARTY_NOTICES.md。

### 后续兼容性修复（同样尚未发布）

- 远端、磁盘缓存和 Bundle JSON 的复数按实际命中的文档语言选择；显式 `language` 与设备 locale 不同也正确。
  数字参数继续沿用格式化 locale，不把翻译语言与数字显示偏好混为一谈。
- 新的默认文本消费者会调用 preload；共享订阅不再抑制失败冷却后的重试，已加载内容仍复用。
- `initialize(contentDeliveryURL: nil, ...)`（或省略 URL）启用纯离线模式：只读 Bundle JSON / 原生资源，
  preload、remoteFetch、语言切换和 clearCache 不发送请求，也不从其他 CDN 项目的缓存恢复文档。
  初始化配置仍不可变；需要远端加载的 App 应在首次初始化时传真实 URL。
- Apple 导出将 signed `%d` / `%ld` / `%lld` 统一为 `%lld`；SDK 会安全提升 Int8/Int16/Int32 参数后格式化。
  新上传工具的这些整数格式使用 Swift Int/Int64 时也兼容旧 SDK；使用 Int32 等小整数需等待本次 SDK 修复发布。

纯离线初始化示例（当前源码 API）：

```swift
Lingora.shared.initialize(
    locale: .current,
    bundledTranslationsDirectory: "Lingora",
    defaultNamespace: "app"
)
```

原来的远端初始化调用不需要修改。已发布的 `0.1.0-dev.3` 仍要求 URL，不能直接省略该参数。
