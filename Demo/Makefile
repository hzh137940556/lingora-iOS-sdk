# Demo 只编排公开 CLI 和独立的 Package 消费验证。
LINGORA_CONFIG ?= ci/lingora.dev.json
LINGORA_APP_OUTPUT ?= LingoraDemo/Generated
LINGORA_COMMON_OUTPUT ?= LingoraCommon/Generated
LINGORA_CLI_VERSION := $(shell tr -d '[:space:]' < lingora-cli.version)
LINGORA := uvx --from "lingora-cli==$(LINGORA_CLI_VERSION)" lingora

.PHONY: build configure-sdk check-sdk check_cli cli-init cli-validate cli-push cli-pull mock_ci check-resources test

# 参数只在显式配置时持久化，Xcode 与构建脚本都读取 sdk-source.json。
configure-sdk:
	python3 scripts/configure_sdk.py $(if $(SDK_MODE),--mode "$(SDK_MODE)") $(if $(SDK_VERSION),--version "$(SDK_VERSION)")

check-sdk:
	python3 scripts/configure_sdk.py --check

build:
	python3 scripts/build_demo.py

check_cli:
	@command -v uv >/dev/null 2>&1 || { echo "错误：未安装 uv，请先安装 uv"; exit 127; }
	@command -v uvx >/dev/null 2>&1 || { echo "错误：未安装 uvx"; exit 127; }

cli-init: check_cli
	$(LINGORA) --config "$(LINGORA_CONFIG)" config init

cli-validate: check_cli
	$(LINGORA) --config "$(LINGORA_CONFIG)" validate --namespaces app --path "$(LINGORA_APP_OUTPUT)"
	$(LINGORA) --config "$(LINGORA_CONFIG)" validate --namespaces common --path "$(LINGORA_COMMON_OUTPUT)"

cli-push: check_cli
	$(LINGORA) --config "$(LINGORA_CONFIG)" push

cli-pull: check_cli
	$(LINGORA) --config "$(LINGORA_CONFIG)" pull --namespaces app --path "$(LINGORA_APP_OUTPUT)"
	$(LINGORA) --config "$(LINGORA_CONFIG)" pull --namespaces common --path "$(LINGORA_COMMON_OUTPUT)"

# 同一 recipe 串行执行，make -j 不能让 push/pull 互相抢跑。
mock_ci:
	$(MAKE) cli-validate
	$(MAKE) cli-push
	$(MAKE) cli-pull
	$(MAKE) cli-validate
	$(MAKE) check-resources

check-resources:
	python3 scripts/check_resources.py --config "$(LINGORA_CONFIG)" \
		--app-output "$(LINGORA_APP_OUTPUT)" --common-output "$(LINGORA_COMMON_OUTPUT)"

test:
	python3 -m unittest discover -s tests -p 'test_*.py' -v
