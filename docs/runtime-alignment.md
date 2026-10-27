# 运行时对齐待决项

本轮覆盖消费接入、CLI、CI 和 SDK 可靠性修复，不改变 SDK 运行时协议或 Demo UI。

| 待决项 | 当前 iOS 行为 | 后续需确定 |
| --- | --- | --- |
| manifest 与可用语言 | 直接请求 language/table；Demo 固定语言列表 | APPLE_SDK 是否提供语言目录、格式与缓存策略；是否必须依赖 manifest |
| 远端语言匹配 | 请求显式 language；Bundle 独立进行 locale 回退 | 精确语言、script、region、基础语言及 defaultLanguage 的顺序 |
| 自动加载 | 初始化恢复缓存，切换后由调用方 fetch | 是否增加 preload/自动加载，保留现有 API 的行为兼容 |
| 默认 namespace | 未传 table 时查询根文档 | 是否增加默认 table，以及对现有调用的影响 |
| 数组翻译 | 普通字符串与 plural | 是否存在 iOS 产品需求、Apple Delivery 数据形状及 Bundle fallback 表达 |

SDK 源码已补齐公开加载状态与失败 namespace、同 URL 请求串行化、同语言刷新顺序保护、
可选失败冷却、外部 JSON 格式化参数校验、plural 数值边界保护和对应回归测试。
JSON/framework 独有语言不再要求主 Bundle 存在对应 lproj。默认 remoteFetch 仍立即重试，
只有显式传入 forceRefresh: false 才启用失败冷却；请求串行化不等于请求合并。
具体 API 和取消语义见 SDK/README.md。上述源码修复尚未发布，Demo 仍固定消费已发布的
0.1.0-dev.2，不会自动使用当前 SDK 源码；验证源码需使用 SDK 测试或显式选择 local。

SwiftUI、Bundle 和 `.stringsdict` 保留平台实现，不照搬 Android 的 Compose、资源 ID 或 Maven 发布方式。
