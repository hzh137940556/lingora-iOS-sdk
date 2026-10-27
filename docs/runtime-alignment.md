# 运行时对齐待决项

本轮只修改消费接入、CLI 和 CI，不改变 SDK 运行时协议或 Demo UI。

| 待决项 | 当前 iOS 行为 | 后续需确定 |
| --- | --- | --- |
| manifest 与可用语言 | 直接请求 language/table；Demo 固定语言列表 | APPLE_SDK 是否提供语言目录、格式与缓存策略；是否必须依赖 manifest |
| 远端语言匹配 | 请求显式 language；Bundle 独立进行 locale 回退 | 精确语言、script、region、基础语言及 defaultLanguage 的顺序 |
| 自动加载 | 初始化恢复缓存，切换后由调用方 fetch | 是否增加 preload/自动加载，保留现有 API 的行为兼容 |
| 默认 namespace | 未传 table 时查询根文档 | 是否增加默认 table，以及对现有调用的影响 |
| 数组翻译 | 普通字符串与 plural | 是否存在 iOS 产品需求、Apple Delivery 数据形状及 Bundle fallback 表达 |

可独立安排的后续可靠性工作：公开加载状态与失败原因、同 language/table 请求合并、
同语言并发刷新顺序保护、失败冷却、格式化参数校验，以及 plural 边界测试。
这些不要求先引入 manifest，但应单独设计 API 和回归测试，避免与接入配置改动混合。

SwiftUI、Bundle 和 `.stringsdict` 保留平台实现，不照搬 Android 的 Compose、资源 ID 或 Maven 发布方式。
