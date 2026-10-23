// 按 Android Demo 的信息架构展示状态、语言切换和可检查的翻译 key。
import Lingora
import LingoraCommon
import SwiftUI

/// 表示 Demo 页面当前可见的 Content Delivery 状态。
private enum DemoLoadState: Equatable {
    case loading
    case ready
    case bundleFallback(String)
}

/// 保存翻译 key 及其当前值，供按钮和弹窗共享。
private struct TranslationExample: Identifiable {
    let table: String
    let key: String
    let value: String

    var id: String { "\(table).\(key)" }
}

/// 复现 Android Demo 的动态文本检查、语言选择和刷新流程。
@MainActor
struct ContentView: View {
    @StateObject private var updater = LingoraSwiftUIUpdater()
    @State private var language = "en-US"
    @State private var loadState = DemoLoadState.loading
    @State private var isRefreshing = false
    @State private var selectedTranslation: TranslationExample?
    @State private var logMessages: [LingoraLogMessage] = []

    private let availableLanguages = ["en-US", "ja", "zh-CN"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(translated("demo_title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(translated("demo_description"))
                statusCard
                Text(translated("current_locale", language))
                Text(translated("available_locales"))
                languagePicker
                Text(translated("tap_key_hint"))
                Text(translated("namespace_app"))
                    .font(.headline)
                ForEach(appExamples) { example in
                    translationButton(for: example)
                }
                CommonNamespaceView(language: language)
                debugLog
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .task { await refresh() }
        .task { await collectLogs() }
        .alert(item: $selectedTranslation) { example in
            Alert(
                title: Text(example.key),
                message: Text(example.value),
                dismissButton: .default(Text(translated("close")))
            )
        }
    }

    /// 使用 SDK 公开更新流让直接读取的翻译值随远端内容刷新。
    private var appExamples: [TranslationExample] {
        _ = updater
        return [
            TranslationExample(table: "app", key: "welcome", value: translated("welcome")),
            TranslationExample(
                table: "app",
                key: "welcome_name",
                value: translated("welcome_name", "iOS")
            ),
            TranslationExample(
                table: "app",
                key: "local_notice",
                value: translated("local_notice")
            ),
            TranslationExample(
                table: "app",
                key: "items_count",
                value: translated("items_count", Int64(3))
            ),
            TranslationExample(table: "app", key: "weekdays", value: translated("weekdays")),
            TranslationExample(table: "app", key: "en_month", value: translated("en_month")),
        ]
    }

    /// 显示 Android Demo 对应的状态信息和刷新动作。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusMessage)
            Button(translated("refresh")) {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 横向展示固定发布语言，并突出当前选项。
    private var languagePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableLanguages, id: \.self) { languageTag in
                    languageButton(languageTag)
                }
            }
        }
    }

    /// 将内部加载状态转换为当前语言的页面文案。
    private var statusMessage: String {
        switch loadState {
        case .loading:
            translated("loading")
        case .ready:
            switch Lingora.shared.lastFetchSource {
            case .network:
                translated("source_network")
            case .cache:
                translated("source_cache")
            case nil:
                translated("source_bundle")
            }
        case .bundleFallback(let reason):
            reason
        }
    }

    /// 使用当前 locale 读取普通字符串。
    private func translated(_ key: String, table: String = "app") -> String {
        Lingora.shared.translate(
            key,
            table: table,
            bundle: .main,
            locale: Locale(identifier: language)
        )
    }

    /// 使用当前 locale 读取带一个格式化参数的字符串或 plural。
    private func translated(
        _ key: String,
        _ argument: CVarArg,
        table: String = "app"
    ) -> String {
        Lingora.shared.translate(
            key,
            argument,
            table: table,
            bundle: .main,
            locale: Locale(identifier: language)
        )
    }

    /// 创建 Android Demo 对应的可选语言按钮。
    private func languageButton(_ languageTag: String) -> some View {
        let isSelected = language.caseInsensitiveCompare(languageTag) == .orderedSame
        return Button {
            Task { await switchLanguage(to: languageTag) }
        } label: {
            Text(languageTag)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary,
                            lineWidth: isSelected ? 2 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 创建占满页面宽度并可检查当前翻译值的 key 按钮。
    private func translationButton(for example: TranslationExample) -> some View {
        Button {
            selectedTranslation = example
        } label: {
            Text("\(example.table).\(example.key)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    /// 切换本地展示 locale；配置远端时同时切换并刷新 SDK 文档。
    private func switchLanguage(to languageTag: String) async {
        language = languageTag
        guard Lingora.shared.isInitialized else {
            loadState = .bundleFallback(translated("source_bundle"))
            return
        }
        do {
            try Lingora.shared.setCustomLocale(
                Locale(identifier: languageTag),
                language: languageTag
            )
            await refresh()
        } catch {
            loadState = .bundleFallback(error.localizedDescription)
        }
    }

    /// 刷新当前语言，并在未配置远端时明确展示 Bundle fallback。
    private func refresh() async {
        guard Lingora.shared.isInitialized else {
            loadState = .bundleFallback(translated("source_bundle"))
            return
        }
        isRefreshing = true
        loadState = .loading
        defer { isRefreshing = false }
        await Lingora.shared.remoteFetch()
        guard !Task.isCancelled else { return }
        loadState = Lingora.shared.lastFetchDate == nil
            ? .bundleFallback(translated("source_remote_unavailable"))
            : .ready
    }

    /// 展示最近的结构化 SDK 日志，便于对照 Android Demo 的运行状态。
    private var debugLog: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(translated("debug_log"))
                .font(.headline)
            if logMessages.isEmpty {
                Text(translated("debug_log_empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(logMessages.suffix(8).enumerated()), id: \.offset) { _, item in
                    Text("[\(item.level.rawValue)] \(item.message)")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    /// 持续收集 SDK 的脱敏结构化日志并限制页面保留数量。
    private func collectLogs() async {
        for await message in Lingora.shared.onLogMessage() {
            guard !Task.isCancelled else { return }
            logMessages.append(message)
            if logMessages.count > 20 {
                logMessages.removeFirst(logMessages.count - 20)
            }
        }
    }
}
