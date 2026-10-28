# iOS Demo 接入与验证

Demo 保持现有 SwiftUI 页面，通过公开 `Lingora` product 展示 `app` 和 `common` namespace。
`LingoraCommon` framework 持有自己的 UI 与 Bundle 资源。以下命令默认从 `Demo/` 执行。

## Swift Package 来源

`sdk-source.json` 是 SDK 来源配置，`make configure-sdk` 将它写入**实际**的
`LingoraDemo.xcodeproj/project.pbxproj`。切换后日常 Xcode 打开的同一工程直接使用所选来源，
构建脚本与 IDE 使用同一依赖。当前默认 dev，固定已发布远端版本 [`0.1.0-dev.3`](https://github.com/hzh137940556/lingora-iOS-sdk/releases/tag/0.1.0-dev.3)。

```json
{
  "mode": "dev",
  "version": "0.1.0-dev.3",
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
# 每次切换远端来源或版本后显式解析，并提交实际生成的 Package.resolved。
python3 scripts/build_demo.py --resolve-only
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
不等于源码回退。普通脚本构建强制使用与配置匹配的 Package.resolved；缺失或过期时直接失败。
切换版本后运行 `python3 scripts/build_demo.py --resolve-only`（或在 Xcode 显式解析），与配置一起提交锁文件。
翻译 CI 在上传前先解析所选远端版本并检查公开 URL，构建阶段使用该解析结果，不静默更新版本。

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
- `pull.format` 使用 `apple-sdk`，路径模板为 `Lingora/{namespace}/{languageTag}.{extension}`，配置目标 `languages`、`namespaces` 和审核 `states`。
- `fileStructureTemplate` 使用 `{languageTag}.lproj/{namespace}.{extension}`。
- 保持 `forceMode=KEEP`、`removeOtherKeys=false`，生成目录不要指向源码目录。

仓库默认配置指向 `Lingora iOS Demo CI`（`1cc50f64-d46f-4360-ab40-561b4317dcaa`）的
`develop` 分支，基础语言为 `en-US`，目标语言为 `ja` / `zh-CN`。

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
JSON 都存在且结构有效，并检查构建产物中的内容完全一致。若只有单个 namespace，应调整检查器。
该门槛不代表所有 key 均已翻译。`KEEP` 不覆盖远端已有非空英语，push 不执行自动翻译或发布 CDN；
成功上传不会在后续构建失败时回滚。

下载使用既有 CLI 的 `apple-sdk` JSON，SDK `0.1.0-dev.3` 开启
`bundledTranslationsDirectory: "Lingora"` 后直接读取 Bundle JSON，避开原生 `.strings`
导出保留 ICU 参数的问题；CLI 和服务端均未修改。

### 上传前 ICU 转换

`make cli-push` / `make mock_ci` 调用 `scripts/push_icu.py`，先将配置的 `.strings`、`.stringsdict` 与 `.xcstrings` 按 namespace/language 合并成临时 JSON，再用固定 CLI 上传。临时配置保留
KEEP、不删除远端 key 等策略，`convertPlaceholdersToIcu=false` 防止二次转换。
不会改写原生资源、下载内容、CLI、服务端或 Android；普通 Xcode build 不运行转换。
直接运行 `lingora push` 会绕过此步骤，iOS 原生源文件请使用上述 Make 入口。

支持普通文本、单个 `%@` → `{arg1}`、单个 signed `%d` / `%ld` / `%lld` → `{arg1, number}`，以及
`.stringsdict` 的独立单变量 `d` / `ld` / `lld` plural → 含 `#` 的标准复数 JSON map。
允许显式位置 `1$`；带参数文本中的 `%%` 保留为字面百分号。
Apple 导出统一为 `%lld`；Swift Int/Int64 可直接消费，小整数 Int8/Int16/Int32 需本次尚未发布的 SDK 提升修复。

`.xcstrings` 支持 1.0 catalog 的源 stringUnit 和独立 plural variation，`sourceLanguage` 必须与配置的
push language 一致。缺省源 stringUnit 时使用 key；`shouldTranslate: false` 不上传，其他语言不作为源文案。
不支持 device/substitutions 或混合变体，避免平铺丢失语义。
当前 Apple 导出器不能保留多参数的索引、宽度/精度、浮点类型或复杂 plural 嵌套，
因此这些输入在上传前失败；字面 ICU 花括号、plural 字面 `#` 和无参数百分号文本也拒绝，
避免现有导出器错误转义。重复 key（同文件或跨文件）同样失败。
这是一条保守、可验证的上传路径，并非完整 printf/ICU 编译器。

本地一次检查全部可解析词条和文件级错误，不要求 API Key、uv 或 CLI 版本，也不访问远端：

```bash
python3 scripts/push_icu.py --config ci/lingora.dev.json --check
# 自动化读取完整的 file/key/namespace/language/message 诊断；有问题时退出码为 1。
python3 scripts/push_icu.py --config ci/lingora.dev.json --check --report-json
```

检查器不会修改源文件；只要存在一个兼容性错误，push 和通用 Action 都不会上传部分成功结果。

`KEEP` 不修复平台已有错误内容或覆盖已有非空英语；历史词条应在平台单独核对。
JSON 结构检查不等于参数语义校验，运行时探针另行验证参数和复数。
`python3 tests/cli_icu_smoke.py` 使用真实固定 CLI 和 localhost 协议 fixture 验证上传、下载和
校验，使用合成凭据，不写真实项目；普通 PR CI 执行该测试。真实环境同步仍受 develop 门禁限制。

从旧 `.strings/.stringsdict` 生成布局迁移时，将两个 target 的旧 `Generated/` 移到工程外备份，
再执行同步。预检拒绝新旧布局混用；不要自动删除或改写已有生成文件来绕过错误。
本地真实流程和 CI 验收通过后可开启翻译同步开关，但工作流仍只在合并后的 develop 执行。
CLI 项目配置不等于 Content Delivery 发布配置，push/pull 不会自动更新运行时 CDN。

本项目的 `iOS Demo Dev` Content Delivery 固定绑定 `develop`，格式为 `apple-sdk`，
路径模板为 `{namespace}/{languageTag}.{extension}`，发布 TRANSLATED/REVIEWED 状态。
公开前缀为 `https://cosly-dev.s3.us-west-2.amazonaws.com/lingora/localstrings/ios-demo-ci/dev`。
当前采用手工发布，翻译修改后需在 Content Delivery 页面发布新快照。

可显式执行以下只读验收（无需 API Key），使用固定发布 SDK 下载六个文档，并检查
namespace、语言切换、字符串参数和复数；先使用无 Bundle 翻译的在线消费者，再使用独立离线消费者：

```bash
LINGORA_CONTENT_DELIVERY_URL=https://cosly-dev.s3.us-west-2.amazonaws.com/lingora/localstrings/ios-demo-ci/dev \
  python3 scripts/check_delivery.py
```

构建后可使用 `python3 scripts/check_delivery.py --app-bundle /path/to/LingoraDemo.app`，
通过远程固定 SDK 验证实际 App/framework 产物的离线 JSON。

## 生成资源与环境地址

- App：`LingoraDemo/Resources/en.lproj` 为基础资源，`LingoraDemo/Generated` 为生成资源。
- Framework：`LingoraCommon/Resources/en.lproj` 为基础资源，`LingoraCommon/Generated` 为生成资源。
- 生成布局为 `Generated/Lingora/{namespace}/{languageTag}.json`；Xcode 将 Lingora 作为文件夹复制，保留层级。
- Xcode 同步目录已覆盖生成资源；不要再次手工添加同一文件。不要在生成目录放入重复的英文基础资源。
- 生成资源只保留在本机或 CI 工作区，不提交 Git。

公开 URL 由 Xcode build setting `LINGORA_CONTENT_DELIVERY_URL` 写入 App Info.plist，
App 从 `LingoraContentDeliveryURL` 读取；默认值为上述 iOS Demo Dev 公开前缀，UI 不变。
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

普通 CI 不使用翻译密钥。`iOS Demo published package` 通过手动提供版本和包含 Demo 的完整 source SHA 验收，
只检出 Demo，下载精确版本并构建；不参与 SDK 发布。真实翻译 CI、变量配置及启用步骤见
[GitHub 配置](../GITHUB_SETUP.md)。业务项目可复制 [CI 模板](ci/examples/README.md)。
