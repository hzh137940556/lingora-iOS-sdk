# Android / iOS 对齐范围

SDK 对齐改动已通过 PR #2 合入，并发布为 `0.1.0-dev.3`。
Demo 当前固定消费该已发布版本，Xcode 配置、Package.resolved 和翻译 CI 版本同步更新；
服务端、Android 与 Demo UI 保持不变。

| Android 实际实现 | iOS 对应实现 | 必要差异 |
| --- | --- | --- |
| preload / refresh | preload / remoteFetch | 保留已发布 iOS 方法名 |
| tFlow 订阅及切换时按需加载 | LingoraText / LingoraSwiftUIUpdater 调用 preload | 使用 SwiftUI 生命周期，普通 translate 不联网 |
| 按语言＋namespace 复用文档、5 秒失败冷却 | 同维度隔离文档及加载标记，切回语言复用内存 | 磁盘恢复后首次 preload 仍检查网络；清理使用代次及磁盘写入屏障 |
| loadMutex 协调 preload / refresh | 加载批次串行、取得执行权后重查缺失项 | 批次内 namespace 并行，SwiftUI 独立监听缓存与语言更新 |
| manifest 提供已发布语言 | availableLanguages 参数 | Apple Delivery 无 manifest，不实现闲置目录下载配置 |
| 精确、显式 script/region、基础语言、defaultLanguage | 同样候选顺序及默认语言行为 | 显式 language 保留 iOS 精确请求兼容性 |
| 默认与附加 namespace | defaultNamespace / namespaces | 原生 Bundle table 不被 namespace 改写 |
| APK 资源回退 | Bundle JSON / 系统 strings、stringsdict 回退 | 保留系统资源及框架 Bundle 隔离 |

已删除额外的 LingoraLanguageOptions 包装、自定义 manifest 下载/缓存、文字系统推断及跨地区排序、
LingoraAutoLoad 三种策略和公开 forceRefresh 参数。不增加数组翻译。

iOS 原生参数与 plural 通过上传前 ICU 转换保持既有服务端/CLI 兼容；复杂有损格式拒绝上传，
KEEP 不修复历史词条。SDK 保留格式校验、plural 边界、刷新顺序及状态测试。
详细用法见 SDK/README.md；上传与 CI 门禁见 Demo/README.md 和 GITHUB_SETUP.md。

## 当前源码的后续修复

以下变更尚未随 SDK 版本发布，Demo 继续固定 `0.1.0-dev.3`：

- CLDR 49 生成的 cardinal 规则与官方样例测试替代手写语言分支；地区、小数和负数修正规则。
- 下载实际字节数上限与 Android 一样在读取时生效，超限保留缓存。
- 可选 swizzling 按允许的 Bundle 隔离；初始化可检查 Bool 结果。
- 默认 SwiftUI 文本共享更新观察对象，保持现有按需加载和回退行为。

不新增 manifest、数组翻译或服务器配置；Android、服务端和 Demo UI 不变。
翻译 CI 改为消费提交的精确版本和锁文件，不再读取远端版本 Variable。

后续 review 修复：文档语言决定 plural，显式语言与设备 locale 不同不再选错类别；
共享观察对象的新消费者仍触发 preload，保留 Android 的失败冷却后重试行为。
与 Android 空 Delivery URL 对齐，省略 iOS URL 可纯离线使用 Bundle JSON / 原生资源。
上传工具完整扫描源词条，支持 signed 单参数和 xcstrings 的普通文本/独立复数；
多参数重排与复杂 catalog 变体仍明确拒绝，不绕过现有导出协议。
