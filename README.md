# Lingora iOS SDK 仓库

这个仓库同时维护可发布 Swift Package、独立 Demo 工程和 CI/CLI 编排，但三者不共享 target：

```text
SDK/                         可发布 Swift Package 根目录
├── Package.swift            Package manifest
├── Sources/Lingora/         Lingora library target
└── Tests/LingoraTests/      LingoraTests test target
Demo/LingoraDemo.xcodeproj/  独立 Xcode 工程
├── LingoraDemo              App target，app namespace
└── LingoraCommon            Framework target，common namespace 与独立 UI
scripts/                     仓库边界和发布脚本，不进入 Package
```

Demo 通过 `Demo/sdk-source.json` 选择 local/dev/release，并由配置命令更新实际 Xcode 工程。
local 引用 `../SDK`，dev/release 引用远端精确版本；两者都只链接公开 `Lingora` product，不回退源码。
切换示例：`make demo-configure SDK_MODE=dev SDK_VERSION=X.Y.Z-dev.N`，随后重新打开 Demo 工程。
当前默认 dev，固定远端版本 `0.1.0-dev.1`；日常 Xcode 与命令行构建使用同一配置，解析失败不会回退本地源码。

SDK 的安装与公开 API 说明见 [SDK/README.md](SDK/README.md)。
本地/远端 Package 消费、CLI 命令和资源打包见 [Demo 接入指南](Demo/README.md)。
业务仓库的自动同步见 [iOS CI 模板](Demo/ci/examples/README.md)。

## Demo 与 CLI

Demo 使用开发项目 `abbf860f-e7cf-423b-8cf2-5ec1fd70ed15`、`develop` 分支、`app` 与
`common` namespace、`en-US` 基础语言以及 `ja` / `zh-CN` 目标语言。

`LingoraDemo` target 持有 `app` UI 和 Bundle fallback；`LingoraCommon` framework target
持有可复用 SwiftUI View、`common` namespace 和自己的 Bundle fallback。两个 target 都只使用
SDK 的公开 API。

Apple CLI 配置位于 `Demo/ci/lingora.dev.json`。push 使用 `KEEP`，保留服务端已有非空值，且不删除
其他 key。pull 分别输出到两个 target 自己的 `Generated/` 目录。普通 Xcode build 不安装或运行 CLI。
只有获得远端写入授权并设置 `LINGORA_API_KEY` 后，才可执行：

```bash
make cli-push
make cli-pull
make mock_ci
```

`Demo/lingora-cli.version` 固定为已安装验收的 CLI 版本。本地 `cli-validate` 不访问真实项目。

## 验证

```bash
make sdk-build
make sdk-test
make package-test
make demo-build
make demo-test
make demo-fixture
make check-boundaries
make release-test
make verify
```

所有 SDK 命令显式使用 `--package-path SDK`。边界检查同时验证 SwiftPM 只有 `Lingora` 与
`LingoraTests` 两个 target，以及 Demo 工程只有 `LingoraDemo` 与 `LingoraCommon` 两个 target。
`demo-fixture` 用真实 SDK 创建临时 Git Package，分别应用 dev/release 配置，在隔离消费者中构建 Demo、校验双 Bundle
生成资源；无网络翻译同步，不修改真实版本 Tag。`make verify` 包含这一检查。
运行时 manifest、语言发现等协议待决项单独记录在 [运行时对齐清单](docs/runtime-alignment.md)。
`package-test` 额外对真实 SDK 的临时 dev/release Tag 执行独立 SwiftPM 解析及 macOS/iOS Simulator
编译，不使用 Demo、翻译服务或本地 path 依赖。发布后同一检查针对真实远端版本执行。

## 发布

普通 PR 和未修改版本文件的分支提交只运行验证。也可在分支同步且工作区干净时手动请求版本：

```bash
make publish-dev VERSION=0.1.0-dev.1  # develop
make publish VERSION=0.1.0            # main
```

`sdk-dev.version` 的变更合入 develop 后自动申请 dev 发布（首次 `0.1.0-dev.1`），等待环境审批；
版本文件未变时不重复发版。上述命令仍可手动请求发布，稳定版继续从 main 发起。

审批后的 CI 会从已验证 source commit 的 `SDK/` 子树创建 package-only snapshot commit，再创建不可移动
SemVer Tag。这样仓库开发分支仍保留 Demo 和脚本，而 SwiftPM 按 Tag 拉取时根目录只包含 SDK Package。

| 渠道 | 来源 | 版本/Tag | GitHub Environment |
| --- | --- | --- | --- |
| dev | `develop` | `X.Y.Z-dev.N` | `ios-sdk-dev` |
| release | `main` | `X.Y.Z` | `ios-sdk-release` |

首次启用前按 [GitHub 配置清单](GITHUB_SETUP.md)配置分支保护、Tag ruleset 和审批环境。
