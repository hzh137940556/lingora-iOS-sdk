# Lingora iOS SDK 开发规范

本仓库在同一个 Git 历史中保存独立 Swift Package、消费它的 Demo App 和 CI 编排代码。

## 通用原则

- 默认使用中文说明，代码标识符、命令和协议字段保持原文。
- 先读实现、测试和配置，做最小完整改动，不提交 Secret、缓存、生成资源或本机配置。
- 新增源码文件、类、函数和方法添加简洁中文职责注释；职责变化时同步更新。
- 使用 Swift 6、Xcode 16 和 iOS 16+；运行时只依赖 Apple 系统框架。

## Package 边界

- `SDK/` 是唯一 Swift Package 根目录；`SDK/Package.swift` 只声明 `Lingora` library target 和 `LingoraTests`，不得包含 Demo target。
- `Demo/LingoraDemo.xcodeproj` 声明 `LingoraDemo` App target 和测试 namespace 隔离的 `LingoraCommon` framework target；两者只通过 `../SDK` local package reference 使用公开 `Lingora` product。
- `SDK/Sources/Lingora` 不得读取 Demo、CLI 配置、App Bundle ID 或 Demo 的 Content Delivery URL；`SDK/` 不得包含仓库级脚本或 Demo 文件。
- 公共 API 保持 Tolgee 风格的 singleton、`initialize`、`remoteFetch`、`translate`、locale 切换和更新流。
- 网络或无效远端数据不得清空最后有效翻译；缓存写入使用原子替换。
- swizzling 默认关闭，只接管普通字符串；plural fallback 继续交给系统资源。

## Demo 与 CLI 边界

- Demo App 通过本地 Swift Package reference 使用公开 product `Lingora`，并链接 `LingoraCommon`；framework 自己持有 UI、`common` namespace 和 Bundle fallback 资源，不读取 SDK 内部类型。
- Demo 在创建 `Lingora` 实例时传入公开 Content Delivery URL；SDK Package 不持有环境 URL。
- `LINGORA_API_KEY` 只用于显式执行的 CLI 进程，不写入 Xcode 配置、源码、日志或示例。
- Demo 只安装 `lingora-cli.version` 固定版本并调用公开命令；普通 Xcode build 不运行 CLI。
- 基础资源位于 `Resources/en.lproj`，生成资源只写 `Generated/` 并忽略提交。

## 验证与发布

```bash
make sdk-build
make sdk-test
make demo-build
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
- 仅明确要求发版时运行 `make publish-dev VERSION=X.Y.Z-dev.N` 或 `make publish VERSION=X.Y.Z`；命令只请求 CI，不在本机创建 Tag。
- 修改后检查两个 target 的实际 diff 和 `git diff --check`，未验证项必须明确说明。
