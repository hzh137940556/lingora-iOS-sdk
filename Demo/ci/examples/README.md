# 业务 iOS 项目的翻译同步 CI

将 `ios-lingora.yml` 复制到业务仓库 `.github/workflows/`。它是模板，不在 SDK 仓库执行。
开发者可只在 CI 使用 CLI，本机正常 Xcode 构建不需要 CLI。

## 接入前配置

1. 按 SDK README 在已有 Xcode 工程添加远端 Package，并关联实际使用它的 App/framework target。
   使用已发布的精确版本，提交该工程的 `Package.resolved`。CI 使用锁文件，不回退本地 SDK。
   如果复制整个 Demo，先用 `make configure-sdk SDK_MODE=release SDK_VERSION=X.Y.Z` 应用配置，
   解析后提交 `sdk-source.json`、工程和锁文件；同时保留 `scripts/configure_sdk.py`，供 Xcode 构建期检查。
2. 复制 Demo 的 `lingora-cli.version` 到仓库根目录，将 `scripts/check_resources.py` 复制到业务仓库
   `ci/check_resources.py`。它只检查 Apple 资源，不是 CLI 实现副本。
3. 参考 `Demo/ci/lingora.dev.json` 创建 `ci/lingora.production.json`，替换真实业务项目、分支、基础资源
   和目标语言。不得直接使用 Demo 项目上传业务词条。配置不包含密钥。
4. pull 使用 `apple-sdk`，布局为 `Lingora/{namespace}/{languageTag}.json`。
   将生成目录关联到正确 target，保留 Lingora 文件夹层级并加入 `.gitignore`。
   初始化 SDK 时传入 `bundledTranslationsDirectory: "Lingora"`，framework 翻译传入自己的 Bundle。
   不要重复添加同语言同 table 的资源。
5. 按项目修改模板的 `XCODE_PROJECT`、`XCODE_SCHEME`、`APP_OUTPUT`、`COMMON_OUTPUT`。
   模板以 Demo 的 app/common 两个 namespace、LingoraCommon.framework 为起点；若 namespace、framework
   名称或 `.app` product 名称不同，同步修改检查器中的 Bundle 映射和工作流产物路径。
   使用 workspace 的项目将 `-project` 改为 `-workspace`。CLI 生成路径必须是专用目录。
6. 将 App 的公开 Delivery URL 接入 build setting 和 Info.plist，初始化时读取，参考 Demo 实现。
   仅传构建参数而不读取不会改变 SDK 地址。保留业务工程已有的其他初始化和资源逻辑。

在业务仓库 Settings → Secrets and variables → Actions 配置：

| 类型 | 名称 | 作用 |
| --- | --- | --- |
| Secret | `LINGORA_API_KEY` | 目标 Lingora 项目和分支的上传、下载权限 |
| Variable | `LINGORA_CONTENT_DELIVERY_URL` | 与该项目、分支、namespace 对应的公开 APPLE_SDK 地址 |

公开 Swift Package 不需要 Maven 凭据。私有 Git 依赖沿用业务团队的只读 Git 认证配置，
不要将 token 拼进依赖 URL、提交到 Package.resolved 或写入 App。

## 执行边界

- `main` push（含合并）触发，普通 PR 不上传文案。按团队规则配置分支保护与触发分支。
- 所有写同一翻译目标的工作流使用相同 concurrency group；上传前拒绝旧提交。
- 固定 CLI → 检查公开 URL / 解析锁定 Package → validate → push → 两个 namespace pull → validate → 必需文件检查 → 使用已解析 Package 构建。
- 必需文件检查要求配置中每种语言的两个 namespace 都有有效的 APPLE_SDK JSON；按产品语言及
  plural 要求调整。validate 成功或文件非空都不代表全量翻译覆盖。
- `KEEP` 保留远端已有非空值，不自动更新已修改的英语；pull 使用 TRANSLATED/REVIEWED 时允许未审核译文。
  生产审核策略需按团队要求调整。
- 不缓存生成资源，不将生成资源写回 Git。成功 push 不会因后续失败回滚；重试仍使用当前提交。
- push/pull 不自动发布 Content Delivery。需要在平台单独确认 APPLE_SDK 格式和发布流程。
- 产物为未签名的模拟器 `.app` 压缩包，保留 7 天，不是可安装到真机的 IPA。
  正式签名、测试和分发沿用业务项目流程，本模板不发布 SDK 或生产 App。

先在团队专用测试项目验收真实 push/pull、远端 Package 下载、资源打包与设备文案，再用于生产。
