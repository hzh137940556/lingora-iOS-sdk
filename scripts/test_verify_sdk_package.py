"""验证发布验收的输入约束与独立消费者依赖声明。"""
import tempfile
from pathlib import Path
import unittest

from verify_sdk_package import validate_repository, write_consumer


class PackageConsumerTests(unittest.TestCase):
    """不联网验证消费者不能携带凭据或依赖本地 SDK。"""

    # 拒绝可能携带凭据或指向本地路径的生产仓库地址。
    def test_repository_validation(self):
        validate_repository("https://github.com/example/sdk.git")
        for url in ("file:///tmp/sdk", "https://secret@example.com/sdk", "https://example.com/sdk?token=x"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                validate_repository(url)

    # 两个渠道的消费者都使用精确版本及真实公开 API。
    def test_consumer_has_exact_version_and_no_source_fallback(self):
        for version in ("0.1.0", "0.1.0-dev.1"):
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                consumer = Path(directory)
                write_consumer(consumer, "https://github.com/example/lingora-iOS-sdk.git", version)
                manifest = (consumer / "Package.swift").read_text()
                self.assertIn(f'exact: "{version}"', manifest)
                self.assertIn('package: "lingora-ios-sdk"', manifest)
                self.assertNotIn(".package(path:", manifest)
                self.assertFalse((consumer / "SDK").exists())
                self.assertIn("Lingora.shared.translate", (consumer / "Sources/PackageProbe/PackageProbe.swift").read_text())


if __name__ == "__main__":
    unittest.main()
