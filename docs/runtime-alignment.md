# Android / iOS 对齐范围

本轮所有修改留在 PR #2，不合并、不发布，服务端、Android 与 Demo UI 不变。
Demo 仍固定消费 `0.1.0-dev.2`；新增 API 的源码测试不代表该已发布版本包含这些接口。

| Android 实际实现 | iOS 对应实现 | 必要差异 |
| --- | --- | --- |
| preload / refresh | preload / remoteFetch | 保留已发布 iOS 方法名 |
| tFlow 订阅及切换时按需加载 | LingoraText / LingoraSwiftUIUpdater 调用 preload | 使用 SwiftUI 生命周期，普通 translate 不联网 |
| 已加载文档复用、5 秒失败冷却 | 共享 preload、只补缺失 namespace、5 秒冷却 | 切换/清缓存使用 iOS generation 保护 |
| manifest 提供已发布语言 | availableLanguages 参数 | Apple Delivery 无 manifest，不实现闲置目录下载配置 |
| 精确、显式 script/region、基础语言、defaultLanguage | 同样候选顺序及默认语言行为 | 显式 language 保留 iOS 精确请求兼容性 |
| 默认与附加 namespace | defaultNamespace / namespaces | 原生 Bundle table 不被 namespace 改写 |
| APK 资源回退 | Bundle JSON / 系统 strings、stringsdict 回退 | 保留系统资源及框架 Bundle 隔离 |

已删除额外的 LingoraLanguageOptions 包装、自定义 manifest 下载/缓存、文字系统推断及跨地区排序、
LingoraAutoLoad 三种策略和公开 forceRefresh 参数。不增加数组翻译。

iOS 原生参数与 plural 通过上传前 ICU 转换保持既有服务端/CLI 兼容；复杂有损格式拒绝上传，
KEEP 不修复历史词条。SDK 保留格式校验、plural 边界、刷新顺序及状态测试。
详细用法见 SDK/README.md；上传与 CI 门禁见 Demo/README.md 和 GITHUB_SETUP.md。
