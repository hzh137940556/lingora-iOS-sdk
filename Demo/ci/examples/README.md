# 业务 iOS 项目的翻译同步 CI

SDK 本身只需要 Swift Package 和公开 Content Delivery URL。需要上传源文案并将翻译打包进 App 时，
再启用本流程；普通 Xcode 构建不运行 CLI。

## 一次性接入

1. 按 SDK README 添加实际已发布的精确版本，关联 App/framework target，提交 `Package.resolved`。
2. 将 `ios-lingora.yml` 放进 `.github/workflows/`。把两处 `REPLACE_WITH_REVIEWED_COMMIT_SHA` 替换为
   **包含该 Action 的、已审阅的开发仓库完整 commit SHA**。该工具随源码提交交付；SDK SemVer Tag
   是 package-only 快照，不含 Action，不能拿 `0.1.0-dev.3` 等 SDK Tag 作为工具版本。
3. 准备以下三个配置文件，不复制或编辑 Python 工具源码：
   - `lingora-cli.version`：固定公开 CLI 版本，例如 `0.1.0rc4`。
   - `ci/lingora.production.json`：参考 Demo 配置，更换真实 Project/Branch、源文件和语言。
     `push.files[].path` 相对此 CLI 配置文件；保留 KEEP 策略，不含密钥。
     pull 使用 `apple-sdk` 和 `Lingora/{namespace}/{languageTag}.{extension}`。
   - `ci/ios-resources.json`：参考同目录示例；key 为 namespace，`output` 相对此映射文件，
     `bundle` 相对构建后的 App。例如 `.`、`Frameworks/MyFeature.framework` 或 `FeatureResources.bundle`。
     可以是一组或多组，不能共享/嵌套输出目录，输出不得包含源文件。
4. 修改工作流的 `XCODE_PROJECT`、`XCODE_SCHEME`、`APP_PRODUCT`。workspace 项目将 `-project`
   改成 `-workspace`。将各生成目录作为保留层级的 Lingora 文件夹加入对应 target，并忽略提交。
   SDK 初始化设置 `bundledTranslationsDirectory: "Lingora"`，framework 调用传自己的 Bundle。
5. App 从 build setting / Info.plist 读取公开 Delivery URL 并传给 SDK；参考 Demo 实现。
   在 GitHub 配置 `LINGORA_CONTENT_DELIVERY_URL` Variable 和 `LINGORA_API_KEY` Secret，后者只放同步步骤。

当前新增工具需先进入可获取的 Git 提交，再填写该提交 SHA。SDK 版本和工具提交分别固定，
升级工具只更新两处 SHA，不需要复制修复代码。许可证尚未确定，本流程不代替项目开源授权。

## 本地使用同一工具

在单独目录检出同一个固定工具提交后，在 macOS 用 Python 3.10+ 和 uv 执行（路径按业务项目调整）：

```bash
python3 /path/to/lingora-tools/Demo/scripts/sync_translations.py \
  --config ci/lingora.production.json --resources ci/ios-resources.json \
  --version-file lingora-cli.version
```

上述命令会写远端，必须先确认目标和设置 `LINGORA_API_KEY`。首次接入先检查全部源文件兼容性，
无需 uv、CLI 或 API Key：

```bash
python3 /path/to/lingora-tools/Demo/scripts/push_icu.py \
  --config ci/lingora.production.json --check --report-json
```

有问题时返回非零退出码并列出所有可解析词条的 file/key 诊断；支持范围包含单参数 signed integer
和 `.xcstrings` 普通文本/独立 plural。多参数重排、device/substitutions 等有损结构仍拒绝。
只检查已有生成文件及 App 打包结果：

```bash
python3 /path/to/lingora-tools/Demo/scripts/sync_translations.py \
  --config ci/lingora.production.json --resources ci/ios-resources.json \
  --check-only --app-bundle /path/to/MyApp.app
```

`--check-only` 不调用 CLI、不联网，不需要 API Key。上传前 ICU 转换的支持范围和拒绝格式见 Demo README；
新工具直接复用同一转换器，不改 CLI、Android 或服务端。

## 执行边界

- 模板仅在 main push（包括合并）执行。所有写同一翻译目标的工作流使用相同 concurrency group，
  上传前拒绝旧提交；普通 PR 不上传。
- 顺序为 URL 校验和锁版本解析 → 本地转换预检 → 所有 namespace validate → 一次 push → 所有 pull →
  所有 validate → JSON 文件检查 → 锁版本构建 → Bundle 归属校验。任何一步失败立即停止。
- 检查要求每个配置语言/namespace 都有合法 JSON；它不保证每个词条都已翻译。KEEP 不覆盖已有非空源文本，
  翻译审核策略继续在业务 CLI 配置中控制。成功 push 不因后续失败回滚。
- 输出目录专用于生成文件，不缓存或提交这些资源。工具不删除文件；旧资源布局需先备份迁移。
- CLI push/pull 不自动发布 CDN，需在平台单独确认 APPLE_SDK 格式和发布配置。
- 产物是未签名模拟器 App，保留 7 天；生产签名、真机测试和发布沿用业务项目流程。

先在获准的测试项目验证真实同步和运行时加载，再启用生产流程。
