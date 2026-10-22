# 转发 SDK、Demo、发布门禁和边界验证，不在正常构建中运行 CLI。
VERSION ?=
SDK_CHANNEL ?= release

.PHONY: sdk-build sdk-test demo-build check-boundaries release-test check-version \
	cli-validate verify publish-dev publish

sdk-build:
	swift build

sdk-test:
	swift test --no-parallel --enable-code-coverage

demo-build:
	xcodebuild -project Demo/LingoraDemo.xcodeproj -scheme LingoraDemo \
		-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

check-boundaries:
	./scripts/check_boundaries.sh

release-test:
	python3 -m unittest discover -s scripts -p 'test_*.py' -v

check-version:
	@python3 scripts/sdk_release.py info --version "$(VERSION)" --channel "$(SDK_CHANNEL)"

cli-validate:
	version=$$(tr -d '[:space:]' < Demo/lingora-cli.version); \
	uvx --from "lingora-cli==$$version" lingora --config Demo/ci/lingora.dev.json validate

verify: check-boundaries release-test sdk-build sdk-test demo-build

publish-dev:
	python3 scripts/sdk_release.py publish --channel dev --version "$(VERSION)"

publish:
	python3 scripts/sdk_release.py publish --channel release --version "$(VERSION)"
