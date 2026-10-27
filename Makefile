# 转发 SDK、Demo、发布门禁和边界验证，不在正常构建中运行 CLI。
VERSION ?=
SDK_CHANNEL ?= release

.PHONY: sdk-build sdk-test demo-build check-boundaries release-test check-version \
	cli-init cli-validate cli-push cli-pull mock_ci demo-configure demo-test demo-fixture verify publish-dev publish

demo-configure:
	$(MAKE) -C Demo configure-sdk

sdk-build:
	swift build --package-path SDK

sdk-test:
	swift test --package-path SDK --no-parallel --enable-code-coverage

demo-build:
	$(MAKE) -C Demo build

demo-test:
	$(MAKE) -C Demo test

demo-fixture:
	python3 Demo/scripts/build_demo.py --fixture-channel dev
	python3 Demo/scripts/build_demo.py --fixture-channel release

check-boundaries:
	./scripts/check_boundaries.sh

release-test:
	python3 -m unittest discover -s scripts -p 'test_*.py' -v

check-version:
	@python3 scripts/sdk_release.py info --version "$(VERSION)" --channel "$(SDK_CHANNEL)"

cli-init cli-validate cli-push cli-pull mock_ci:
	$(MAKE) -C Demo $@

verify: check-boundaries release-test sdk-build sdk-test demo-test demo-build demo-fixture

publish-dev:
	python3 scripts/sdk_release.py publish --channel dev --version "$(VERSION)"

publish:
	python3 scripts/sdk_release.py publish --channel release --version "$(VERSION)"
