"""验证 CLI 串行/失败边界、远端消费者和 Apple 资源门禁。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

DEMO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEMO / "scripts"))
from configure_sdk import configure
from check_resources import check, read_resource


class IntegrationTests(unittest.TestCase):
    """使用隔离工作区和命令替身，不连接远端项目。"""

    # 命令替身记录执行顺序，并模拟指定步骤失败。
    def run_make(self, root: Path, fail: str = "") -> subprocess.CompletedProcess:
        shutil.copy(DEMO / "Makefile", root / "Makefile")
        shutil.copy(DEMO / "lingora-cli.version", root / "lingora-cli.version")
        binary = root / "bin"
        binary.mkdir()
        (binary / "uv").write_text("#!/bin/sh\nexit 0\n")
        (binary / "uv").chmod(0o755)
        stub = '''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as stream:
    stream.write(json.dumps(args) + "\\n")
if os.environ.get("FAIL") in args:
    sys.exit(19)
'''
        (binary / "uvx").write_text(stub)
        (binary / "uvx").chmod(0o755)
        # 检查器命令同样记录，但资源语义由独立测试覆盖。
        (root / "scripts").mkdir()
        (root / "scripts/check_resources.py").write_text(stub.split("\n", 1)[1])
        return subprocess.run(
            ["make", "-j8", "mock_ci", "LINGORA_CONFIG=ci/custom config.json"],
            cwd=root, capture_output=True, text=True,
            env={**os.environ, "PATH": f"{binary}:{os.environ['PATH']}",
                 "CALLS": str(root / "calls"), "FAIL": fail},
        )

    # 即使并行 Make，两个 namespace 也必须按 validate/push/pull/validate 顺序执行。
    def test_parallel_make_is_serial_and_uses_selected_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_make(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
            self.assertEqual([call[5] for call in calls[:-1]],
                             ["validate", "validate", "push", "pull", "pull", "validate", "validate"])
            version = (DEMO / "lingora-cli.version").read_text().strip()
            for call in calls[:-1]:
                self.assertEqual(call[:5], ["--from", f"lingora-cli=={version}", "lingora",
                                           "--config", "ci/custom config.json"])
            self.assertIn("--app-output", calls[-1])

    # 任意上传或下载失败都不能继续执行后续步骤。
    def test_failure_stops_pipeline(self):
        for failure, expected in (("push", 3), ("pull", 4), ("validate", 1)):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                result = self.run_make(root, failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len((root / "calls").read_text().splitlines()), expected)

    # 构造双 Bundle 资源并验证缺失、空值及错包都会失败。
    def test_required_and_packaged_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config.json"
            config.write_text(json.dumps({"pull": {"languages": ["ja"], "format": "apple-sdk",
                "fileStructureTemplate": "Lingora/{namespace}/{languageTag}.{extension}"}}))
            outputs = {"app": root / "app", "common": root / "common"}
            app = root / "App.app"
            for namespace, output in outputs.items():
                bundle = app if namespace == "app" else app / "Frameworks/LingoraCommon.framework"
                for target in (output, bundle):
                    path = target / "Lingora" / namespace
                    path.mkdir(parents=True)
                    (path / "ja.json").write_text(json.dumps({"welcome": "Hello", "items_count": {
                        "variations": {"plural": {"other": "%lld items"}}}}))
            check(config, outputs, app)
            packaged = app / "Frameworks/LingoraCommon.framework/Lingora/common/ja.json"
            packaged.write_text('{"welcome": "Wrong"}')
            with self.assertRaises(ValueError):
                check(config, outputs, app)
            generated = outputs["app"] / "Lingora/app/ja.json"
            generated.write_text('{}')
            with self.assertRaises(ValueError):
                check(config, outputs)
            generated.unlink()
            with self.assertRaises(FileNotFoundError):
                check(config, outputs)

    # JSON 结构门禁拒绝缺失 other、未知变体和空值，避免构建携带坏资源。
    def test_invalid_sdk_documents(self):
        invalid = [[], {}, {"": "value"}, {"hello": ""}, {"hello": 1},
                   {"items": {"variations": {"plural": {"one": "%lld item"}}}},
                   {"items": {"variations": {"plural": {"other": "", "one": "one"}}}},
                   {"items": {"variations": {"plural": {"other": "items", "bogus": "bad"}}}}]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ja.json"
            for value in invalid:
                with self.subTest(value=value):
                    path.write_text(json.dumps(value))
                    with self.assertRaises(ValueError):
                        read_resource(path)


if __name__ == "__main__":
    unittest.main()
