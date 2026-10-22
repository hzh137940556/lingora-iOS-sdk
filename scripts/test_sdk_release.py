# 验证 SwiftPM 版本渠道、Git 来源、审批门禁和 CI 调度，不访问真实远端。
from __future__ import annotations

import contextlib
import copy
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError

import sdk_release as sdk


# 覆盖 dev 与 release 的 SemVer、来源和审批环境映射。
class ReleaseTests(unittest.TestCase):
    # 两渠道必须使用 SwiftPM 可识别且互不混淆的版本形式。
    def test_channels_have_distinct_versions_and_sources(self) -> None:
        cases = (
            ("dev", "0.1.0-dev.1", "develop", "ios-sdk-dev"),
            ("release", "0.1.0", "main", "ios-sdk-release"),
        )
        for channel, version, branch, environment in cases:
            with self.subTest(channel=channel):
                release = sdk.Release(channel, version)
                self.assertEqual(release.tag, version)
                self.assertEqual(release.branch, branch)
                self.assertEqual(release.environment, environment)

    # dev 必须带递增预发布号，release 必须是纯稳定 SemVer。
    def test_invalid_channel_versions_are_rejected(self) -> None:
        invalid = (
            ("dev", "0.1.0"),
            ("dev", "0.1.0-dev"),
            ("dev", "0.1.0-dev.01"),
            ("release", "0.1.0-dev.1"),
            ("release", "v0.1.0"),
            ("release", "01.2.3"),
            ("release", "0.1"),
            ("release", "0.1.0\n"),
        )
        for channel, version in invalid:
            with self.subTest(channel=channel, version=version), self.assertRaises(ValueError):
                sdk.Release(channel, version)
        with self.assertRaises(ValueError):
            sdk.Release("production", "0.1.0")

    # CI 输出需要保留审批界面和后续发布使用的完整字段。
    def test_report_records_release_fields(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            summary = Path(directory) / "summary"
            release = sdk.Release("dev", "0.1.0-dev.1")
            with patch.dict(sdk.os.environ, {"GITHUB_STEP_SUMMARY": str(summary)}):
                with contextlib.redirect_stdout(io.StringIO()):
                    sdk.report(release, "abc123", output)
            contents = output.read_text(encoding="utf-8")
            self.assertIn("tag=0.1.0-dev.1\n", contents)
            self.assertIn("environment=ios-sdk-dev\n", contents)
            self.assertIn("sha=abc123\n", contents)
            self.assertIn("[dev] — 0.1.0-dev.1", summary.read_text(encoding="utf-8"))


# 使用隔离 Git 仓库验证提交、Tag 和本地发布门禁。
class SourceTests(unittest.TestCase):
    # 构造 main、develop 和对应远端引用，不接触工作仓库。
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.addCleanup(patch.stopall)
        patch.object(sdk, "ROOT", self.root).start()
        self.run_git("init", "--initial-branch=main")
        self.run_git("config", "user.name", "Release Test")
        self.run_git("config", "user.email", "release-test@example.invalid")
        self.run_git("commit", "--allow-empty", "-m", "base")
        self.main_sha = self.run_git("rev-parse", "HEAD")
        self.run_git("update-ref", "refs/remotes/origin/main", self.main_sha)
        self.run_git("checkout", "-b", "develop")
        self.run_git("commit", "--allow-empty", "-m", "development")
        self.dev_sha = self.run_git("rev-parse", "HEAD")
        self.run_git("update-ref", "refs/remotes/origin/develop", self.dev_sha)

    # 所有测试 Git 命令只运行在临时仓库。
    def run_git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL,
        ).strip()

    # develop 的未合并提交可发 dev，但不能发 release。
    def test_branch_history_controls_channel(self) -> None:
        sdk.check_source(sdk.Release("dev", "0.1.0-dev.1"), self.dev_sha)
        sdk.check_source(sdk.Release("release", "0.1.0"), self.main_sha)
        with self.assertRaisesRegex(ValueError, "origin/main"):
            sdk.check_source(sdk.Release("release", "0.1.0"), self.dev_sha)

    # workflow_dispatch 必须来自正确分支并锁定事件 SHA。
    def test_verify_request_locks_branch_and_sha(self) -> None:
        release = sdk.Release("dev", "0.1.0-dev.1")
        with patch.object(sdk, "fetch_source"):
            self.assertEqual(
                sdk.verify_request(release, "branch", "develop", self.dev_sha),
                self.dev_sha,
            )
            with self.assertRaisesRegex(ValueError, "develop"):
                sdk.verify_request(release, "branch", "main", self.dev_sha)
            with self.assertRaisesRegex(ValueError, "commit SHA"):
                sdk.verify_request(release, "branch", "develop", self.main_sha)
            with self.assertRaisesRegex(ValueError, "develop"):
                sdk.verify_request(release, "tag", "develop", self.dev_sha)

    # 初次请求拒绝重复 Tag，审批后重试只允许同一 SHA 的 Tag。
    def test_existing_tag_is_only_allowed_for_approved_retry(self) -> None:
        release = sdk.Release("dev", "0.1.0-dev.1")
        self.run_git("tag", release.tag, self.dev_sha)
        with patch.object(sdk, "fetch_source"):
            with self.assertRaisesRegex(ValueError, "Tag 已存在"):
                sdk.verify_request(release, "branch", "develop", self.dev_sha)
            self.assertEqual(
                sdk.verify_request(
                    release,
                    "branch",
                    "develop",
                    self.dev_sha,
                    allow_existing_tag=True,
                ),
                self.dev_sha,
            )
        self.run_git("tag", "-f", release.tag, self.main_sha)
        with patch.object(sdk, "fetch_source"):
            with self.assertRaisesRegex(ValueError, "其他提交"):
                sdk.verify_request(
                    release,
                    "branch",
                    "develop",
                    self.dev_sha,
                    allow_existing_tag=True,
                )

    # 本地发版拒绝错误分支和脏工作区，不触发 CI。
    def test_local_publish_requires_correct_clean_branch(self) -> None:
        with self.assertRaisesRegex(ValueError, "main"):
            sdk.publish(sdk.Release("release", "0.1.0"))
        (self.root / "pending.txt").write_text("pending", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "未提交"):
            sdk.publish(sdk.Release("dev", "0.1.0-dev.1"))

    # 本地校验失败不能触发 GitHub Actions 或创建 Tag。
    def test_failed_verification_does_not_dispatch(self) -> None:
        release = sdk.Release("dev", "0.1.0-dev.1")
        real_run = subprocess.run

        # 只让 make verify 失败，保留发布前 Git 检查的真实执行。
        def fail_make(command: list[str], **kwargs):
            if command[0] == "make":
                raise subprocess.CalledProcessError(1, command)
            return real_run(command, **kwargs)

        with patch.object(sdk, "fetch_source"):
            with patch.object(sdk.subprocess, "run", side_effect=fail_make) as execute:
                with self.assertRaises(subprocess.CalledProcessError):
                    sdk.publish(release)
        self.assertFalse(any(call.args[0][0] == "gh" for call in execute.call_args_list))
        self.assertEqual(self.run_git("tag", "--list"), "")

    # 通过本地门禁后只 dispatch 对应分支，Tag 留给审批后的 CI 创建。
    def test_local_publish_dispatches_ci_without_creating_tag(self) -> None:
        release = sdk.Release("dev", "0.1.0-dev.1")
        real_run = subprocess.run
        external_commands: list[list[str]] = []

        # 模拟 make 和 gh，Git 状态检查仍使用真实临时仓库。
        def capture_external(command: list[str], **kwargs):
            if command[0] in {"make", "gh"}:
                external_commands.append(command)
                return subprocess.CompletedProcess(command, 0)
            return real_run(command, **kwargs)

        with patch.object(sdk, "fetch_source"):
            with patch.object(sdk.subprocess, "run", side_effect=capture_external):
                with contextlib.redirect_stdout(io.StringIO()):
                    sdk.publish(release)
        self.assertEqual(external_commands[0], ["make", "verify"])
        self.assertEqual(
            external_commands[1],
            [
                "gh", "workflow", "run", "ci.yml", "--ref", "develop",
                "-f", "channel=dev", "-f", "version=0.1.0-dev.1",
            ],
        )
        self.assertEqual(self.run_git("tag", "--list"), "")


# 检查发布环境缺失或放宽时必须失败。
class EnvironmentTests(unittest.TestCase):
    # 构造与 Android SDK 相同审批人策略的有效环境。
    def setUp(self) -> None:
        self.release = sdk.Release("dev", "0.1.0-dev.1")
        self.environment = {
            "can_admins_bypass": False,
            "protection_rules": [{
                "type": "required_reviewers",
                "prevent_self_review": False,
                "reviewers": [{"type": "User", "reviewer": {"login": "hzh137940556"}}],
            }],
            "deployment_branch_policy": {
                "custom_branch_policies": True,
                "protected_branches": False,
            },
        }

    # 两渠道只允许自己的来源分支。
    def test_valid_environment_for_each_channel(self) -> None:
        for channel, version, branch in (
            ("dev", "0.1.0-dev.1", "develop"),
            ("release", "0.1.0", "main"),
        ):
            with self.subTest(channel=channel):
                sdk.validate_environment(
                    sdk.Release(channel, version),
                    self.environment,
                    {"branch_policies": [{"type": "branch", "name": branch}]},
                )

    # 无审批人、额外审批人、禁止自审和管理员绕过都不允许发版。
    def test_incorrect_approval_policy_is_rejected(self) -> None:
        variants = []
        missing = copy.deepcopy(self.environment)
        missing["protection_rules"] = []
        variants.append(missing)
        extra = copy.deepcopy(self.environment)
        extra["protection_rules"][0]["reviewers"].append(
            {"type": "User", "reviewer": {"login": "another-reviewer"}},
        )
        variants.append(extra)
        no_self_review = copy.deepcopy(self.environment)
        no_self_review["protection_rules"][0]["prevent_self_review"] = True
        variants.append(no_self_review)
        bypass = copy.deepcopy(self.environment)
        bypass["can_admins_bypass"] = True
        variants.append(bypass)
        for environment in variants:
            with self.subTest(environment=environment), self.assertRaises(ValueError):
                sdk.validate_environment(
                    self.release,
                    environment,
                    {"branch_policies": [{"type": "branch", "name": "develop"}]},
                )

    # 宽泛、跨渠道、Tag 或多余规则不能替代唯一来源分支。
    def test_only_expected_branch_is_allowed(self) -> None:
        for policies in (
            [],
            [{"type": "branch", "name": "*"}],
            [{"type": "branch", "name": "main"}],
            [{"type": "tag", "name": "develop"}],
            [
                {"type": "branch", "name": "develop"},
                {"type": "branch", "name": "main"},
            ],
        ):
            with self.subTest(policies=policies), self.assertRaises(ValueError):
                sdk.validate_environment(
                    self.release,
                    self.environment,
                    {"branch_policies": policies},
                )

    # API 鉴权、缺失环境和网络错误不能被当作审批已配置。
    def test_environment_api_failures_stop_release(self) -> None:
        with patch.dict(sdk.os.environ, {"GH_TOKEN": "test-only-token"}):
            failures = [
                HTTPError("https://api.github.com", code, "test", {}, None)
                for code in (401, 403, 404, 500)
            ]
            failures.append(URLError("offline"))
            for failure in failures:
                with self.subTest(failure=failure), patch.object(sdk, "urlopen", side_effect=failure):
                    with self.assertRaises(ValueError):
                        sdk.check_environment(self.release, "hzh137940556/lingora-iOS-sdk")

    # 环境校验失败时不得向后续发布 Job 导出字段。
    def test_cli_does_not_export_without_valid_environment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            with patch.object(sdk, "verify_request", return_value="abc123"):
                with patch.object(sdk, "check_environment", side_effect=ValueError("missing")):
                    with contextlib.redirect_stderr(io.StringIO()):
                        result = sdk.main([
                            "verify-request",
                            "--channel", "release",
                            "--version", "0.1.0",
                            "--ref-type", "branch",
                            "--ref-name", "main",
                            "--expected-sha", "abc123",
                            "--repository", "hzh137940556/lingora-iOS-sdk",
                            "--github-output", str(output),
                        ])
            self.assertEqual(result, 1)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
