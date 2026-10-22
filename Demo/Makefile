# Demo 只消费固定 CLI 和本地 Package product。
LINGORA_CLI_VERSION := $(shell tr -d '[:space:]' < lingora-cli.version)
LINGORA := uvx --from "lingora-cli==$(LINGORA_CLI_VERSION)" lingora

.PHONY: build check_cli cli-validate cli-push cli-pull mock_ci

build:
	xcodebuild -project LingoraDemo.xcodeproj -scheme LingoraDemo \
		-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

check_cli:
	@command -v uv >/dev/null 2>&1 || { echo "错误：未安装 uv，请先安装 uv"; exit 127; }

cli-validate: check_cli
	$(LINGORA) --config ci/lingora.dev.json validate

cli-push: check_cli
	$(LINGORA) --config ci/lingora.dev.json push

cli-pull: check_cli
	$(LINGORA) --config ci/lingora.dev.json pull

mock_ci: cli-validate cli-push cli-pull
