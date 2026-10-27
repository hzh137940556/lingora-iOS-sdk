"""验证 Apple 源文件的 ICU 转换、安全拒绝和临时配置边界。"""
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

DEMO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEMO / "scripts"))
from push_icu import convert_text, convert_file, prepare


class IcuUploadTests(unittest.TestCase):
    """覆盖支持范围、拒绝行为和真实源文件转换。"""
    # 格式约束来自当前 Apple 导出器，不能假装支持有损的复杂 printf。
    def test_text_and_unsupported_formats(self):
        self.assertEqual(convert_text("Hello %@"), "Hello {arg1}")
        self.assertEqual(convert_text("%1$lld items"), "{arg1, number} items")
        self.assertEqual(convert_text("%@: 100%%"), "{arg1}: 100%")
        self.assertEqual(convert_text("%lld items", plural=True), "# items")
        self.assertEqual(convert_text("one item", plural=True), "one item")
        for text in ("%@ %@", "%2$@", "%d", "%.2f", "%n", "%*d", "%#@x@", "literal {name}", "100%", "%@ %1$@"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                convert_text(text)
        with self.assertRaises(ValueError):
            convert_text("# %lld", plural=True)

    # 实际 Demo 资源按 namespace 合并为 JSON，原文件和 KEEP 策略保持不变。
    def test_demo_sources_and_configuration(self):
        source = DEMO / "ci/lingora.dev.json"
        before = source.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            config = json.loads(prepare(source, Path(temporary)).read_text())
            self.assertEqual(len(config["push"]["files"]), 2)
            self.assertEqual(config["push"]["forceMode"], "KEEP")
            self.assertFalse(config["push"]["removeOtherKeys"])
            self.assertFalse(config["push"]["convertPlaceholdersToIcu"])
            for item in config["push"]["files"]:
                values = json.loads(Path(item["path"]).read_text())
                if item["namespace"] == "app":
                    self.assertIn("{arg1}", values["welcome_name"])
                self.assertIn("#", values["items_count"]["other"])
        self.assertEqual(source.read_bytes(), before)

    # 重复 key（包括转义后的同名 key）及不支持的 plural 必须在上传前失败。
    def test_duplicate_and_invalid_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "test.strings"
            path.write_text('"a" = "first";\n"a" = "second";')
            with self.assertRaises(ValueError):
                convert_file(path)
            path.write_text('/* comment */ "url" = "https://example.com"; // end\n')
            self.assertEqual(convert_file(path), {"url": "https://example.com"})
            path = path.with_suffix(".stringsdict")
            path.write_bytes(plistlib.dumps({"count": {"NSStringLocalizedFormatKey": "prefix %#@count@"}}))
            with self.assertRaises(ValueError):
                convert_file(path)
            path.write_text('<plist version="1.0"><dict><key>x</key><dict/><key>x</key><dict/></dict></plist>')
            with self.assertRaisesRegex(ValueError, "Duplicate key"):
                convert_file(path)


if __name__ == "__main__":
    unittest.main()
