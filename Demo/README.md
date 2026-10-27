# iOS Demo 接入与验证

Demo 保持现有 SwiftUI 页面，通过公开 `Lingora` product 展示 `app` 和 `common` namespace。
`LingoraCommon` framework 持有自己的 UI 与 Bundle 资源。以下命令默认从 `Demo/` 执行。

## Swift Package 来源

`sdk-source.json` 是 SDK 来源配置，`make configure-sdk` 将它写入**实际**的
`LingoraDemo.xcodeproj/project.pbxproj`。切换后日常 Xcode 打开的同一工程直接使用所选来源，
构建脚本不再在临时副本中偷偷选择另一种依赖。当前没有可用的已发布 Tag，因此默认保留 local。

```json
{
  "mode": "local",
  "version": "",
  "repositoryURL": "https://github.com/hzh137940556/lingora-iOS-sdk.git",
  "localPath": "../SDK"
}
```

| mode | 来源 | version |
| --- | --- | --- |
| local | 相对 Demo 的 localPath | 空字符串 |
| dev | repositoryURL 的远端 Package | 精确 `X.Y.Z-dev.N` |
| release | repositoryURL 的远端 Package | 精确 `X.Y.Z` |

先关闭该 Xcode 工程，再运行以下命令；远端版本请替换为实际已发布的版本：

```bash
make configure-sdk SDK_MODE=local
make configure-sdk SDK_MODE=dev SDK_VERSION=X.Y.Z-dev.N
make configure-sdk SDK_MODE=release SDK_VERSION=X.Y.Z
open LingoraDemo.xcodeproj
```

配置命令同时保存 JSON 和工程依赖，并保留两个 target 的公开 `Lingora` product 关联。
也可以先编辑 JSON，再执行 `make configure-sdk` 应用；修改配置文件本身不会让 Xcode 自动重新解析依赖。
如果要修改本地路径或仓库地址，也可使用 `scripts/configure_sdk.py --local-path ../另一个目录`
或 `--repository-url https://example.com/sdk.git`。本地路径使用可移植的相对路径，不提交机器绝对路径。

`make check-sdk` 检查配置与工程一致；普通构建与 Xcode Build Phase 也会检查，发现漂移时停止并提示
重新配置。检查阶段不会自动改写工程，也不会调用 CLI。Xcode 会先解析 Package，配置修改后应先应用再
重新打开工程，不能依赖 Build Phase 在解析前切换来源。两份文件应一并提交；切换不清理其他依赖或用户代码。

远端模式只声明 `XCRemoteSwiftPackageReference` 的 `exactVersion`，不读取 `localPath`、不要求本地 SDK
存在。版本缺失、格式错误、渠道不匹配或远端解析失败都会报错，绝不回退源码。正常 SwiftPM 缓存复用
不等于源码回退；切换版本后 Xcode 会按新的精确依赖更新 Package.resolved，远端配置提交时一并保留该锁文件。

```bash
# 使用当前已应用的配置构建，与 Xcode 相同。
make build

# 无真实远端写入的两渠道消费者验收。
python3 scripts/build_demo.py --fixture-channel dev
python3 scripts/build_demo.py --fixture-channel release
```

fixture 是测试专用入口：将真实 SDK 放入临时 Git 仓库，通过同一配置函数改写隔离的 Demo 工程，
使用精确 dev/release Tag 构建 App/framework，验证两个 Bundle 的资源。消费者没有 SDK 目录，
localPath 指向不存在的位置；随后请求一个不存在的精确版本，确认 SwiftPM 报错且不复用旧版本。
测试不修改当前工程选择、不创建真实版本 Tag。测试中的 file URL 仅在
fixture 内部开放，正常配置只接受无凭据 HTTPS URL。
临时中日资源复制自英文，不代表真实翻译。所有构建使用独立 DerivedData，退出后清理；
可用 `--artifact /新目录/LingoraDemo.app` 保留模拟器产物，目标路径必须尚不存在。

已有业务项目的 Xcode 与 Package.swift 接入步骤见 [SDK 指南](../SDK/README.md)。

## CLI 安装与本地配置

本机需要 Xcode 16+、Python 3、Make 和 `uv`/`uvx`。CLI 来自主项目的 PyPI 包，
固定版本保存在 `lingora-cli.version`；当前 `0.1.0rc4` 为预发布版本，不在本仓库复制 CLI 实现。

```bash
uvx --from "lingora-cli==$(cat lingora-cli.version)" lingora --version

# 创建一个新配置；不要覆盖现有 Demo 配置。
make cli-init LINGORA_CONFIG=ci/lingora.local.json
```

`config init` 只生成通用配置，不会自动推断 iOS 工程。参考 `ci/lingora.dev.json` 编辑新文件：

- `apiUrl`、`projectId`、`branch` 指向你的翻译项目；branch 是 Lingora 分支。
- `push.files` 为每个 namespace 列出基础 `.strings` 和 `.stringsdict`，language 为 `en-US`。
- `pull.format` 使用 `apple-strings-stringdict`，配置目标 `languages`、`namespaces` 和审核 `states`。
- `fileStructureTemplate` 使用 `{languageTag}.lproj/{namespace}.{extension}`。
- 保持 `forceMode=KEEP`、`removeOtherKeys=false`，生成目录不要指向源码目录。

JSON 内相对路径以配置文件目录为基准；命令行 `--path` 以当前工作目录为基准。
Demo Makefile 分别覆盖 app/common 输出目录，避免 `emptyDir=true` 清理另一个 namespace 的资源。

```bash
# 本地校验不需要密钥，不访问真实项目。
make cli-validate LINGORA_CONFIG=ci/lingora.local.json

# 显式需要上传/下载时，通过终端环境或密钥管理器提供 LINGORA_API_KEY。
# 请勿将实际密钥写入命令、配置文件、构建参数或提交到 Git。
make cli-push LINGORA_CONFIG=ci/lingora.local.json
make cli-pull LINGORA_CONFIG=ci/lingora.local.json

# 串行 validate → push → 两次 pull → 两次 validate → 必需文件检查。
make mock_ci LINGORA_CONFIG=ci/lingora.local.json
```

API Key 由 CLI 读取环境变量；不进入 App。按项目约定提交无凭据配置，个人配置自行忽略。
可通过 `LINGORA_APP_OUTPUT`、`LINGORA_COMMON_OUTPUT` 改变输出，但也必须同步调整 Xcode 资源目录。
`make -j8 mock_ci` 仍严格串行，任一步失败即停止。不要把它作为普通 Xcode build phase。

`validate` 可能对空输出目录成功；`check-resources` 另行要求每种目标语言的 app/common
`.strings` 和 `.stringsdict` 都存在且非空。若项目没有 plural 或只有单个 namespace，应调整检查器。
该门槛不代表所有 key 均已翻译。`KEEP` 不覆盖远端已有非空英语，push 不执行自动翻译或发布 CDN；
成功上传不会在后续构建失败时回滚。

## 生成资源与环境地址

- App：`LingoraDemo/Resources/en.lproj` 为基础资源，`LingoraDemo/Generated` 为生成资源。
- Framework：`LingoraCommon/Resources/en.lproj` 为基础资源，`LingoraCommon/Generated` 为生成资源。
- Xcode 同步目录已覆盖生成资源；不要再次手工添加同一文件。不要在生成目录放入重复的英文基础资源。
- 生成资源只保留在本机或 CI 工作区，不提交 Git。

公开 URL 由 Xcode build setting `LINGORA_CONTENT_DELIVERY_URL` 写入 App Info.plist，
App 从 `LingoraContentDeliveryURL` 读取；默认值仍为原 Demo 开发地址，UI 不变。
SDK Package 不持有地址。构建脚本将同名环境变量显式转成 Xcode 参数，覆盖工程默认值：

```bash
LINGORA_CONTENT_DELIVERY_URL=https://cdn.example.com/apple make build
LINGORA_CONTENT_DELIVERY_URL='' make build  # 只使用 Bundle fallback
```

直接运行 xcodebuild 时必须显式传入 `"LINGORA_CONTENT_DELIVERY_URL=$LINGORA_CONTENT_DELIVERY_URL"`；
不能假设环境变量会覆盖工程设置。业务 CI 必须检查地址非空，并确认对应的 Project/Branch/namespace。
URL 是公开信息，不能包含 API Key。构建成功不表示 CDN 已发布或设备运行已验收。

## 本地与 CI 验证

```bash
make test
make check-resources
python3 scripts/build_demo.py --check-resources
```

`make test` 使用命令替身和临时资源测试顺序、失败停止和打包检查，不执行真实 push/pull。
仓库根目录 `make verify` 还运行 SDK 测试、发布规则测试、本地 Demo 和真实 SDK fixture 消费构建。

普通 CI 不使用翻译密钥。发布后的 `iOS Demo published package` 只检出 Demo，下载精确版本并构建；
也可手动提供版本和包含 Demo 的完整 source SHA 重跑。真实翻译 CI、变量配置及启用步骤见
[GitHub 配置](../GITHUB_SETUP.md)。业务项目可复制 [CI 模板](ci/examples/README.md)。
