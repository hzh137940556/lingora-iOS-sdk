# iOS SDK 仓库配置与发布步骤

仓库：[hzh137940556/lingora-iOS-sdk](https://github.com/hzh137940556/lingora-iOS-sdk)。
下面是 CI 发版所需的 GitHub 配置清单；提交工作流不会自动修改仓库 Settings。

## 1. Actions 与默认权限

在仓库 Settings → Actions 启用 Actions。保持默认 `GITHUB_TOKEN` 只读；工作流仅在审批后的
publish Job 为当前 Job 申请 `contents: write`，PR 和普通分支验证保持只读。不需要保存 PAT、
API Key 或其他发版 Secret。

工作流文件必须先进入默认分支，GitHub 才能稳定提供 `workflow_dispatch`。首次建立远端历史时，
先通过正常 PR 合并 CI 文件，再尝试发布。

## 2. 分支保护

在 Settings → Rules → Rulesets 为 `develop`、`main` 配置分支规则：

1. 通过 PR 合并并禁止强推、删除。
2. 必需检查使用显示名 **`iOS SDK CI`**。
3. 不把 publish Job 设为 PR 必需检查；它只在手动发版时运行。
4. 审核人数和管理员绕过策略由仓库所有者确认，不能用临时关闭规则解决发版问题。

## 3. 保护 SwiftPM 版本 Tag

创建 Active Tag ruleset，include pattern 使用 `*.*.*`，启用 Restrict updates 和
Restrict deletions，不允许移动或删除已发布版本。版本格式仍由 `scripts/sdk_release.py` 严格限制为：

- dev：`X.Y.Z-dev.N`
- release：`X.Y.Z`

不要限制 publish Job 创建新 Tag；不要手工创建版本 Tag。SwiftPM 以 Tag 作为版本，Tag 出现即代表
源码包已经可解析，因此工作流会在验证和环境审批完成后，使用已验证提交的 `SDK/` 子树生成一个
package-only snapshot commit，再对该 commit 创建 Tag。Tag 展开的根目录只有 Package 内容，不包含
Demo、CLI 或仓库脚本。

## 4. 配置双渠道人工审批

在 Settings → Environments 创建两个环境：

| 渠道 | Environment | 唯一允许的来源 |
| --- | --- | --- |
| dev | `ios-sdk-dev` | Branch `develop` |
| release | `ios-sdk-release` | Branch `main` |

两个环境分别配置相同保护：

1. Required reviewers 仅添加 `hzh137940556`。
2. 不勾选 Prevent self-review，允许维护者自己批准。
3. 关闭 Allow administrators to bypass configured protection rules。
4. Deployment branches and tags 选择 Selected branches and tags。
5. 各环境只添加表中的一条 **Branch** 规则，不添加 Tag、通配或另一渠道分支。
6. 不配置 Environment Secret。

发布脚本会在进入审批前和审批后通过 GitHub API 校验真实配置；环境缺失、权限不足、审批策略放宽、
来源规则错误都会停止，不会回退到无保护环境。

## 5. 发布预发布与稳定版本

`sdk-dev.version` 声明待发布的开发版本，当前为 `0.1.0-dev.2`。包含该文件变更的 PR 合入 develop 后，
push CI 自动提出发布请求、完成验证并等待 `ios-sdk-dev` 环境审批；批准后创建远端版本并验证消费。
普通 PR 检查不发布，版本文件未变的后续 push 不重复发布；下一次自动发版需在 PR 中递增该文件。
稳定版继续由 main 手动发起。不得移动既有 Tag，也不得同时为同一版本重复发起发布。

也可以手动发起发布。维护者本机需要 Python 3、Swift 6、Xcode 16、Make、已登录的 GitHub CLI `gh`。先把代码合并到
正确分支，并保证本地分支干净且与 `origin` 同步：

```bash
# develop
make publish-dev VERSION=0.1.0-dev.2

# main
make publish VERSION=0.1.0
```

命令会先运行完整 `make verify`，然后 dispatch `ci.yml`，不会在本机创建或推送 Tag。Actions 会：

1. 再次验证版本、来源分支、commit SHA、环境配置、SDK tests、Demo build 和边界门禁。
2. 等待对应 Environment 审批。
3. 审批后再次锁定同一 source SHA，从其 `SDK/` 子树生成 package-only snapshot commit，并创建 annotated SemVer Tag。
4. 创建 GitHub Release；dev 标记为 prerelease，release 为稳定版本。
5. 自动运行 `Published Swift Package verification`：仅检出 scripts，在独立消费者中解析刚发布的精确版本，
   校验 Package 根目录、公开 API 和 macOS/iOS Simulator 编译，不依赖 Demo 的后续接入改动。

publish Job 失败时先看 Tag 是否已经创建。如果 Tag 尚未创建，可修复后使用新 dispatch；如果 Tag 已创建且
snapshot 的父提交和目录树都对应已验证 source SHA，只重试原 publish Job 完成 GitHub Release。不要删除或
移动 Tag，代码修复必须递增版本。

## 6. 消费验证

发布 PR 合入 develop 后，经既有环境审批和发布验收成功，`0.1.0-dev.2` 即可通过远端精确版本消费。
无需等待 Demo 接入改动合入，也不需要再手动 dispatch 首次发布；不得手工创建 Tag。
Demo 切换到该版本在 Demo 自己的 PR 中完成。合并完成不等于发布完成，审批或发布失败时版本仍不可用。

`make package-test` 验证当前 SDK 的临时 dev/release 版本，不创建真实 Tag。
发布后的自动验收不检出 SDK 或 Demo，不允许源码回退。可在 Actions 手动运行
`Published Swift Package verification`，提供 channel、version 和包含验收脚本的完整 source SHA。
如果下载验收失败，已发布 Tag 不回滚；修复网络后可重跑验收，SDK 代码修复必须使用新版本。
包编译验证不代表 App UI、设备运行或 Content Delivery 已验收，也不切换 Demo 的 SDK 来源。

稳定版本使用范围依赖：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    from: "0.1.0"
)
```

预发布版本固定精确 SemVer，避免自动漂移：

```swift
.package(
    url: "https://github.com/hzh137940556/lingora-iOS-sdk.git",
    exact: "0.1.0-dev.2"
)
```

发布完成后用一个不含 SDK 源码副本的独立消费工程解析仓库 URL 和固定版本；本地 Demo 的 local package
reference 只能证明 target 边界和源码构建通过，不能替代真实远端 SwiftPM 下载验收。

Demo 的 `iOS Demo published package` 是独立手动验收工作流：提供已发布版本和包含 Demo 配置脚本的
完整 source SHA，只检出 Demo，以同一配置命令应用 dev/release，再构建 App 和 framework。
SDK 发布与独立 Package 验收在单独 PR 中维护，不依赖此 Demo 工作流。
该检查不需要 Lingora API Key；模拟器构建成功不代表真机安装、UI 或 CDN 内容已经验收。

## 7. Demo 翻译同步 CI

`.github/workflows/ios-demo-translations.yml` 在 develop 的 Demo/工作流变更或手动选择 develop 时运行。
首次启用前，先确认 `Demo/ci/lingora.dev.json` 的 Project/Branch 是获准使用的开发翻译目标，
确认目标语言与 plural 已有可下载内容，然后在 Actions 设置中添加：

| 类型 | 名称 | 值/用途 |
| --- | --- | --- |
| Secret | `LINGORA_API_KEY` | 该项目和分支的上传/下载密钥 |
| Variable | `LINGORA_CONTENT_DELIVERY_URL` | 对应 APPLE_SDK 的公开 URL，不能为空 |
| Variable | `LINGORA_IOS_SDK_VERSION` | 实际已发布的固定 dev 版本 `X.Y.Z-dev.N` |
| Variable | `LINGORA_TRANSLATIONS_ENABLED` | 配置完成后设置 `true`，允许真实同步 |

未启用时同步 Job 跳过，普通 PR 与 `make verify` 始终不写翻译服务。工作流进入默认分支后才能
稳定使用手动入口。手动选择非 develop 分支不会同步，上传前还会拒绝落后于最新 develop 的提交。

启用后流程为配置并解析固定 SDK / 检查公开 URL → 固定 CLI → validate → push → app/common pull → validate → 必需文件检查 →
远端固定版本 Package 构建 → 检查生成资源进入正确 Bundle → 已发布 SDK 离线加载产物验证 → 上传模拟器 App ZIP（保留 7 天）。
只检出 Demo，在上传前通过同一配置命令应用固定 dev 版本，不允许本地 SDK 源码兜底。API Key 仅用于同步步骤，不传给 Xcode。
成功 push 不因后续失败回滚，KEEP 不覆盖已有非空值；CLI 同步不会自动发布 Content Delivery。

当前配置使用既有 CLI 的 `apple-sdk` JSON 下载，SDK `0.1.0-dev.2` 读取 Bundle JSON，
避开原生 `.strings` 导出的 ICU 参数兼容问题。本地真实同步、打包及离线/在线运行时验证通过后
可启用 `LINGORA_TRANSLATIONS_ENABLED=true`；PR 未合并期间不会执行 develop 自动同步。CDN 指向
`https://cosly-dev.s3.us-west-2.amazonaws.com/lingora/localstrings/ios-demo-ci/dev`。
密钥仅包含词条创建/编辑/查看和翻译编辑/查看权限，不具备 CDN 发布权限。

普通 CI 另有 `Published SDK runtime and CDN` Job，在公开 URL 变量非空时只读验收公开 CDN，
不传 Secret、不执行 push/pull，并在独立消费者中校验 JSON 离线加载。PR 合并前可验证实际发布 SDK 的运行时加载；真实翻译同步仍
仅限 develop，且必须等工作流合入后才能在 GitHub 执行。不要为预合并验收放宽分支门禁。
首次验收需分别确认 Actions 步骤、产物内资源、模拟器运行与 CDN 内容；真机 IPA 沿用独立签名流程。
业务仓库可复制 [消费项目 CI 模板](Demo/ci/examples/README.md)，无需使用本仓库的发布权限。


## 8. 日常 Demo 配置与普通 CI

`Demo/sdk-source.json` 与实际 `project.pbxproj` 一起维护。先关闭 Xcode，再执行
`make demo-configure SDK_MODE=local` 或带固定版本的 dev/release 配置，随后重新打开工程。
仅修改 JSON 时须再执行配置命令；构建期的检查只报告不一致，不会切换依赖。

普通 `make verify` 验证当前工程配置，并额外在隔离消费者中验证 dev/release fixture。
CI 不自动改写提交中的选择：若提交远端模式，其版本必须已经存在。fixture 使用真实 SDK 源码的
临时 Git Tag，不需要翻译服务密钥，也不代表真实发布成功。
Demo 手动验收与翻译同步在各自 Runner 检出中应用精确远端模式，不影响开发者本地配置。


### iOS 上传兼容性与普通 PR 验证

Demo 的 `make mock_ci` 在 push 前通过 `Demo/scripts/push_icu.py` 将受支持的原生资源转换为
临时 ICU JSON，再调用固定 `lingora-cli.version`。复杂格式在远端写入前失败；不修改服务端或
Android，不自动修复历史词条。业务 CI 模板使用同一脚本，详见 Demo README。
普通 PR CI 额外执行 `Demo/tests/cli_icu_smoke.py`：真实固定 CLI 只连接 localhost 协议 fixture，
使用合成凭据验证 multipart 上传、ZIP 下载和 validate，不读取 GitHub Secret，不写真实项目。
SDK 的可选语言目录、默认 namespace 与自动加载测试使用隔离网络和缓存；Demo 仍锁定已发布版本。
