# 运行时对齐范围

本轮在 PR #2 中补齐 SDK 可靠性、可选接入策略和 iOS 上传转换；不合并、不发布，
不修改服务端、Android 或 Demo UI。Demo 仍固定消费 `0.1.0-dev.2`；新增 SDK API 只存在于源码。

| 项目 | 已实现行为 | 边界 |
| --- | --- | --- |
| 上传 ICU | iOS 原生资源经临时 JSON 调用固定 CLI | 单参数/单变量 plural；有损格式拒绝，KEEP 不修复历史内容 |
| 默认 namespace | 默认用于远端和 Bundle JSON，显式 table 优先 | 不改变原生 Bundle table |
| 语言匹配 | 可选静态列表、同语言/文字系统匹配、显式默认语言 | 显式 language 保持精确；不跨简繁猜测 |
| 语言目录 | 可选 locales manifest、条件请求与离线缓存 | Apple Delivery 不自动生成，默认不依赖目录 |
| 自动加载 | 手动、仅初始化、初始化及切换三种策略 | 默认手动，同步 translate 不请求网络 |
| 数组翻译 | 本轮不做 | 等待业务需求与 Apple 数据协议 |

SDK 源码已补齐加载状态、同 URL 请求串行化、最新刷新保护、可选失败冷却、
外部 JSON 格式校验、plural 数值边界保护和对应测试。JSON/framework 独有语言无需主 Bundle lproj。
具体 API、取消语义见 SDK/README.md；上传转换约束和 CI 接入见 Demo/README.md。
协议 fixture 验证不等于真实远端项目验收；真实同步仍只在合并后的 develop 门禁下执行。
