"""验证 Apple 源文件的 ICU 转换、安全拒绝和临时配置边界。"""
import json
from pathlib import Path
import plistlib
import os
import subprocess
import sys
import tempfile
import unittest

DEMO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEMO / "scripts"))
from push_icu import convert_text, convert_file, prepare, collect_sources, CompatibilityError


class IcuUploadTests(unittest.TestCase):
    """覆盖支持范围、拒绝行为和真实源文件转换。"""
    # 格式约束来自当前 Apple 导出器，不能假装支持有损的复杂 printf。
    def test_text_and_unsupported_formats(self):
        self.assertEqual(convert_text("Hello %@"), "Hello {arg1}")
        self.assertEqual(convert_text("%1$lld items"), "{arg1, number} items")
        self.assertEqual(convert_text("%@: 100%%"), "{arg1}: 100%")
        self.assertEqual(convert_text("%lld items", plural=True), "# items")
        self.assertEqual(convert_text("one item", plural=True), "one item")
        for specifier in ("d", "ld", "lld"):
            self.assertEqual(convert_text(f"%{specifier} files"), "{arg1, number} files")
            self.assertEqual(convert_text(f"%1${specifier} files", plural=True), "# files")
        for text in ("%@ %@", "%2$@", "%u", "%.2f", "%n", "%*d", "%#@x@", "literal {name}", "100%", "%@ %1$@"):
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

    # Catalog 只读取源语言，支持直接文本和 plural，保留显式不翻译语义。
    def test_catalog_supported_subset(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.xcstrings"
            catalog = {"version": "1.0", "sourceLanguage": "en-US", "strings": {
                "implicit source": {},
                "skip": {"shouldTranslate": False},
                "hello": {"localizations": {"en-US": {"stringUnit": {"state": "translated", "value": "Hello %@"}},
                                             "ja": {"stringUnit": {"state": "translated", "value": "別の翻訳"}}}},
                "items": {"localizations": {"en-US": {"variations": {"plural": {
                    "one": {"stringUnit": {"value": "%d item"}},
                    "other": {"stringUnit": {"value": "%d items"}}
                }}}}}
            }}
            path.write_text(json.dumps(catalog))
            before = path.read_bytes()
            self.assertEqual(convert_file(path, "en-US"), {
                "implicit source": "implicit source", "hello": "Hello {arg1}",
                "items": {"one": "# item", "other": "# items"}})
            self.assertEqual(path.read_bytes(), before)
            with self.assertRaisesRegex(CompatibilityError, "sourceLanguage"):
                convert_file(path, "ja")
            path.write_text('{"version":"1.0","sourceLanguage":"en","strings":{"x":{},"x":{}}}')
            with self.assertRaisesRegex(CompatibilityError, "Duplicate key"):
                convert_file(path)

    # signed d 的 stringsdict 经 ICU 转换后仍使用标准计数语义。
    def test_signed_integer_plural(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Localizable.stringsdict"
            path.write_bytes(plistlib.dumps({"count": {
                "NSStringLocalizedFormatKey": "%#@count@", "count": {
                    "NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "d",
                    "one": "%d file", "other": "%d files"}}}))
            self.assertEqual(convert_file(path), {"count": {"one": "# file", "other": "# files"}})

    # 一次报告跨文件全部不兼容词条；既不生成部分上传文件，也不调用 CLI。
    def test_complete_source_scan_and_no_partial_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "first.strings").write_text('"multiple" = "%@ %@"; "precision" = "%.2f"; "valid" = "%d files";')
            (root / "second.xcstrings").write_text(json.dumps({"version": "1.0", "sourceLanguage": "en", "strings": {
                "device": {"localizations": {"en": {"variations": {"device": {}}}}},
                "substitution": {"localizations": {"en": {"substitutions": {}}}}
            }}))
            config = {"push": {"files": [{"path": file, "namespace": "feature", "language": "en"}
                                        for file in ("first.strings", "second.xcstrings")]}}
            path = root / "config.json"
            path.write_text(json.dumps(config))
            _, issues = collect_sources(config, path)
            self.assertEqual({item["key"] for item in issues}, {"multiple", "precision", "device", "substitution"})
            generated = root / "generated"
            generated.mkdir()
            with self.assertRaises(CompatibilityError):
                prepare(path, generated)
            self.assertEqual(list(generated.iterdir()), [])
            result = subprocess.run([sys.executable, str(DEMO / "scripts/push_icu.py"), "--config", str(path),
                                     "--check", "--report-json"], capture_output=True, text=True,
                                    env={key: value for key, value in os.environ.items() if key != "LINGORA_API_KEY"})
            self.assertEqual(result.returncode, 1)
            self.assertEqual(len(json.loads(result.stdout)["issues"]), 4)
            self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
