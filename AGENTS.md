# Lingora iOS SDK 开发规范

本仓库在同一个 Git 历史中保存独立 Swift Package、消费它的 Demo App 和 CI 编排代码。

## 通用原则

- 默认使用中文说明，代码标识符、命令和协议字段保持原文。
- 先读实现、测试和配置，做最小完整改动，不提交 Secret、缓存、生成资源或本机配置。
- 新增源码文件、类、函数和方法添加简洁中文职责注释；职责变化时同步更新。
- 使用 Swift 6、Xcode 16 和 iOS 16+；运行时只依赖 Apple 系统框架。

## Package 边界

- `SDK/` 是唯一 Swift Package 根目录；`SDK/Package.swift` 只声明 `Lingora` library target 和 `LingoraTests`，不得包含 Demo target。
- `Demo/LingoraDemo.xcodeproj` 声明 `LingoraDemo` App target 和测试 namespace 隔离的 `LingoraCommon` framework target；两者只通过同一配置选定的 local 或 remote package reference 使用公开 `Lingora` product。
- `SDK/Sources/Lingora` 不得读取 Demo、CLI 配置、App Bundle ID 或 Demo 的 Content Delivery URL；`SDK/` 不得包含仓库级脚本或 Demo 文件。
- 公共 API 保持 Tolgee 风格的 singleton、`initialize`、`remoteFetch`、`translate`、locale 切换和更新流。
- 网络或无效远端数据不得清空最后有效翻译；缓存写入使用原子替换。
- swizzling 默认关闭，只接管普通字符串；plural fallback 继续交给系统资源。

## Demo 与 CLI 边界

- Demo App 通过配置选定的 Swift Package reference 使用公开 product `Lingora`，并链接 `LingoraCommon`；framework 自己持有 UI、`common` namespace 和 Bundle fallback 资源，不读取 SDK 内部类型。
- Demo 在创建 `Lingora` 实例时传入公开 Content Delivery URL；SDK Package 不持有环境 URL。
- `LINGORA_API_KEY` 只用于显式执行的 CLI 进程，不写入 Xcode 配置、源码、日志或示例。
- Demo 只安装 `lingora-cli.version` 固定版本并调用公开命令；普通 Xcode build 不运行 CLI。
- 基础资源位于 `Resources/en.lproj`，生成资源只写 `Generated/` 并忽略提交。
- `Demo/sdk-source.json` 统一配置 local/dev/release；`configure_sdk.py` 将选择持久化到实际 Xcode 工程，配置与工程必须一致。普通构建和 Xcode 检查但不自动改写。
- local 只读取相对 `localPath`，version 为空；dev 必须为 `X.Y.Z-dev.N`，release 必须为 `X.Y.Z`，都使用 exactVersion，远端不访问或回退本地 SDK。
- fixture 是测试专用入口，使用同一配置逻辑在无 SDK 的隔离消费者验证两个渠道，file URL 仅测试可用，不修改当前工程选择。
- Demo 公开 URL 由 build setting 写入 Info.plist；CI 必须显式注入，不能静默使用工程开发默认值。
- CLI 顺序固定为 validate/push/pull/validate/资源检查，即使 `make -j` 也必须串行，失败立即退出。
- 真实翻译工作流仅在 develop 且 `LINGORA_TRANSLATIONS_ENABLED=true` 时运行，Secret 仅用于 CLI 步骤。

## 验证与发布

```bash
make sdk-build
make sdk-test
make demo-build
make demo-configure SDK_MODE=local
make demo-test
make demo-fixture
make check-boundaries
make release-test
make verify
```

- 真实 push/pull 需要明确授权和 `LINGORA_API_KEY`，普通验证不得写远端。
- SwiftPM 直接通过 SemVer Tag 分发源码，不存在独立二进制上传步骤；Tag 指向由 `SDK/` 子树生成的 package-only snapshot commit，只能由审批后的 CI publish Job 创建。
- dev 渠道使用 `develop` 上的 `X.Y.Z-dev.N`，进入 `ios-sdk-dev` 环境；release 渠道使用 `main` 上的 `X.Y.Z`，进入 `ios-sdk-release` 环境。
- `scripts/sdk_release.py` 统一校验版本、来源分支、提交 SHA、`SDK/` 子树、审批环境和重复 Tag；不得绕过脚本手工发布。
- 两个环境只允许对应来源 Branch，审批人和管理员绕过策略必须与脚本、测试及 `GITHUB_SETUP.md` 一致。
- 发布前运行完整 `make verify`；只有 publish Job 拥有 `contents: write`，不得移动或覆盖已有 Tag。
- `make package-test` 用真实 SDK 创建临时 dev/release Tag 并编译独立消费者，不能使用 Demo 或本地 path 依赖代替版本解析；生成物只保留在临时目录。
- 发布后由 `sdk-package-smoke.yml` 只检出 scripts、解析远端精确版本并验证 macOS/iOS Simulator 编译；SDK 发布验收不依赖 Demo 接入 PR，Demo 是否切换版本独立维护。
- `sdk-dev.version` 的变更合入 develop 后自动申请对应 dev 版本发布；保留完整验证和环境人工审批，其他 push 不重复发版，稳定版仍手动发起。
- 仅明确要求发版时运行 `make publish-dev VERSION=X.Y.Z-dev.N` 或 `make publish VERSION=X.Y.Z`；命令只请求 CI，不在本机创建 Tag。
- 修改后检查两个 target 的实际 diff 和 `git diff --check`，未验证项必须明确说明。
