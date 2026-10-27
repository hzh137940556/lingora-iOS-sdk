"""验证日常 Xcode 工程的来源切换、固定版本和失败边界。"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

DEMO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEMO / "scripts"))
from configure_sdk import configure


class SDKSourceTests(unittest.TestCase):
    """在独立工程副本中执行真实配置命令，避免改动开发者的选择。"""

    # 为每个测试提供真实 pbxproj、配置脚本和最小本地 Package 路径。
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.demo = self.root / "Demo"
        self.project = self.demo / "LingoraDemo.xcodeproj/project.pbxproj"
        self.project.parent.mkdir(parents=True)
        shutil.copy(DEMO / "LingoraDemo.xcodeproj/project.pbxproj", self.project)
        (self.demo / "scripts").mkdir()
        shutil.copy(DEMO / "scripts/configure_sdk.py", self.demo / "scripts")
        (self.root / "SDK").mkdir()
        (self.root / "SDK/Package.swift").write_text("// Test package marker\n")
        self.config = self.demo / "sdk-source.json"
        self.config.write_text(json.dumps({
            "mode": "local", "version": "", "localPath": "../SDK",
            "repositoryURL": "https://example.com/sdk.git",
        }))
        configure(self.demo)

    # 使用同一 CLI 改写真实工程；反复切换保留其他配置和两个 product 绑定。
    def test_cli_round_trip_is_idempotent(self):
        original = self.project.read_text()
        command = [sys.executable, str(self.demo / "scripts/configure_sdk.py")]
        for mode, version in (("dev", "1.2.3-dev.4"), ("release", "1.2.3")):
            subprocess.run([*command, "--mode", mode, "--version", version], check=True, capture_output=True)
            config = json.loads(self.config.read_text())
            self.assertEqual((config["mode"], config["version"]), (mode, version))
            text = self.project.read_text()
            self.assertIn("kind = exactVersion", text)
            self.assertIn(f'version = "{version}"', text)
            self.assertNotIn("XCLocalSwiftPackageReference", text)
            self.assertNotIn("../SDK", text)
            configure(self.demo)
            self.assertEqual(text, self.project.read_text())
            subprocess.run([*command, "--check"], check=True, capture_output=True)
        subprocess.run([*command, "--mode", "local"], check=True, capture_output=True)
        self.assertEqual(original, self.project.read_text())

    # 来源与版本非法时不能部分修改工程或已保存配置。
    def test_invalid_selection_preserves_both_files(self):
        before = (self.config.read_bytes(), self.project.read_bytes())
        cases = [
            {"mode": "unknown"},
            {"mode": "dev", "version": "1.2.3"},
            {"mode": "release", "version": "1.2.3-dev.1"},
            {"mode": "dev", "version": "latest"},
            {"mode": "dev", "version": ""},
            {"mode": "release", "version": "01.2.3"},
            {"mode": "release", "version": "main"},
            {"mode": "local", "localPath": "../missing"},
            {"mode": "local", "localPath": "/machine/local/sdk"},
            {"mode": "dev", "version": "1.2.3-dev.1", "repositoryURL": "file:///tmp/sdk"},
            {"mode": "dev", "version": "1.2.3-dev.1", "repositoryURL": "https://secret@example.com/sdk"},
        ]
        for selection in cases:
            with self.subTest(selection=selection), self.assertRaises(ValueError):
                configure(self.demo, selection)
            self.assertEqual(before, (self.config.read_bytes(), self.project.read_bytes()))

    # 完全没有本地 SDK 时，两种远端配置都能应用；不会读取或生成本地替代引用。
    def test_remote_never_requires_local_source(self):
        shutil.rmtree(self.root / "SDK")
        for mode, version in (("dev", "1.0.0-dev.1"), ("release", "1.0.0")):
            configure(self.demo, {"mode": mode, "version": version, "localPath": "../missing"})
            configure(self.demo, check=True)
            self.assertNotIn("relativePath", self.project.read_text())
            self.assertFalse((self.root / "SDK").exists())

    # 手工只改 JSON 或 Xcode 中只改依赖都会让构建前检查失败。
    def test_check_rejects_config_or_project_drift(self):
        config = json.loads(self.config.read_text())
        config.update(mode="release", version="2.0.0")
        self.config.write_text(json.dumps(config))
        with self.assertRaisesRegex(ValueError, "mismatch"):
            configure(self.demo, check=True)
        configure(self.demo)
        self.project.write_text(self.project.read_text().replace('version = "2.0.0"', 'version = "1.0.0"'))
        with self.assertRaisesRegex(ValueError, "mismatch"):
            configure(self.demo, check=True)

    # 本地自定义相对路径包含空格时仍生成合法的 Xcode 字符串。
    def test_custom_local_path(self):
        target = self.root / "自定义 SDK"
        target.mkdir()
        (target / "Package.swift").write_text("// Test package marker\n")
        configure(self.demo, {"localPath": "../自定义 SDK"})
        self.assertIn('relativePath = "../自定义 SDK";', self.project.read_text())
        configure(self.demo, check=True)


if __name__ == "__main__":
    unittest.main()
