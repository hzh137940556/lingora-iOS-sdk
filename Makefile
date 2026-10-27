# 转发 SDK、Demo、发布门禁和边界验证，不在正常构建中运行 CLI。
VERSION ?=
SDK_CHANNEL ?= release

.PHONY: sdk-build sdk-test package-test demo-build check-boundaries release-test check-version \
	cli-validate cli-push cli-pull mock_ci verify publish-dev publish

sdk-build:
	swift build --package-path SDK

sdk-test:
	swift test --package-path SDK --no-parallel --enable-code-coverage

demo-build:
	xcodebuild -project Demo/LingoraDemo.xcodeproj -scheme LingoraDemo \
		-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

check-boundaries:
	./scripts/check_boundaries.sh

release-test:
	python3 -m unittest discover -s scripts -p 'test_*.py' -v

check-version:
	@python3 scripts/sdk_release.py info --version "$(VERSION)" --channel "$(SDK_CHANNEL)"

package-test:
	python3 scripts/verify_sdk_package.py --fixture --channel dev --version 0.0.0-dev.1
	python3 scripts/verify_sdk_package.py --fixture --channel release --version 0.0.0

cli-validate cli-push cli-pull mock_ci:
	$(MAKE) -C Demo $@

verify: check-boundaries release-test sdk-build sdk-test demo-build package-test

publish-dev:
	python3 scripts/sdk_release.py publish --channel dev --version "$(VERSION)"

publish:
	python3 scripts/sdk_release.py publish --channel release --version "$(VERSION)"
