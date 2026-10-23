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

维护者本机需要 Python 3、Swift 6、Xcode 16、Make、已登录的 GitHub CLI `gh`。先把代码合并到
正确分支，并保证本地分支干净且与 `origin` 同步：

```bash
# develop
make publish-dev VERSION=0.1.0-dev.1

# main
make publish VERSION=0.1.0
```

命令会先运行完整 `make verify`，然后 dispatch `ci.yml`，不会在本机创建或推送 Tag。Actions 会：

1. 再次验证版本、来源分支、commit SHA、环境配置、SDK tests、Demo build 和边界门禁。
2. 等待对应 Environment 审批。
3. 审批后再次锁定同一 source SHA，从其 `SDK/` 子树生成 package-only snapshot commit，并创建 annotated SemVer Tag。
4. 创建 GitHub Release；dev 标记为 prerelease，release 为稳定版本。

publish Job 失败时先看 Tag 是否已经创建。如果 Tag 尚未创建，可修复后使用新 dispatch；如果 Tag 已创建且
snapshot 的父提交和目录树都对应已验证 source SHA，只重试原 publish Job 完成 GitHub Release。不要删除或
移动 Tag，代码修复必须递增版本。

## 6. 消费验证

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
    exact: "0.1.0-dev.1"
)
```

发布完成后用一个不含 SDK 源码副本的独立消费工程解析仓库 URL 和固定版本；本地 Demo 的 local package
reference 只能证明 target 边界和源码构建通过，不能替代真实远端 SwiftPM 下载验收。
