"""将受支持的 Apple 基础资源转为 ICU JSON，再调用固定版本的公开 CLI。"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


# 仅接受当前 Apple 导出器能够无损恢复的单参数格式。
def convert_text(text: str, plural: bool = False) -> str:
    if not isinstance(text, str):
        raise ValueError("Translation must be text")
    if any(character in text for character in "{}") or (plural and "#" in text):
        raise ValueError("Literal ICU braces or plural # cannot round-trip through Apple export")
    result = []
    cursor = 0
    parameters = 0
    while cursor < len(text):
        if text[cursor] != "%":
            result.append(text[cursor])
            cursor += 1
            continue
        match = re.match(r"%(?:%|(?:1\$)?(?:@|lld|ld|d))", text[cursor:])
        if not match:
            raise ValueError("Only one %@, %d, %ld or %lld parameter is supported; width/precision/reordering are rejected")
        token = match.group()
        cursor += len(token)
        if token == "%%":
            result.append("%")
            continue
        parameters += 1
        if parameters > 1 or (plural and token.endswith("@")):
            raise ValueError("Apple export cannot preserve multiple parameters or plural object arguments")
        result.append("#" if plural else "{arg1, number}" if token.endswith("d") else "{arg1}")
    # 无参数调用不会执行 printf；双百分号会在下载后保持双写，故拒绝歧义文本。
    if parameters == 0 and "%" in text and not plural:
        raise ValueError("Percent-only strings need an explicit application formatting contract")
    return "".join(result)


# 使用 Apple 自带解析器读取 .strings，拒绝重复 key 后再转为 JSON。
def read_strings(path: Path) -> dict:
    raw = path.read_bytes()
    text = raw.decode("utf-16" if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else "utf-8-sig")
    token = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|(?P<entry>"(?:\\.|[^"\\])*"\s*=\s*"(?:\\.|[^"\\])*"\s*;)', re.S)
    cursor = 0
    entries = 0
    while cursor < len(text):
        match = token.match(text, cursor)
        if not match:
            raise ValueError("Only quoted Apple strings entries and comments are supported")
        entries += match["entry"] is not None
        cursor = match.end()
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], capture_output=True, check=True)
    values = json.loads(result.stdout)
    if len(values) != entries:
        raise ValueError(f"Duplicate key in {path.name}")
    return values


# 保存可机器读取的完整诊断；错误只包含文件和 key，不输出源文本或配置凭据。
class CompatibilityError(ValueError):
    def __init__(self, issues: list[dict]):
        self.issues = issues
        super().__init__("\n".join(f"{item['file']}, key {item['key'] or '<file>'}: {item['message']}" for item in issues))


# JSON 不允许重复 key，避免 catalog 条目在解析时被静默覆盖。
def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate key: {key}")
        result[key] = value
    return result


# 解析原生资源，但不在此阶段转换单个词条，便于完整扫描所有错误。
def read_entries(path: Path, language: str | None):
    if path.suffix == ".strings":
        return read_strings(path), None
    if path.suffix == ".stringsdict":
        data = path.read_bytes()
        document = ET.fromstring(data)
        for dictionary in document.iter("dict"):
            keys = [key.text for key in dictionary.findall("key")]
            if len(keys) != len(set(keys)):
                raise ValueError("Duplicate key in stringsdict")
        values = plistlib.loads(data)
        if not isinstance(values, dict):
            raise ValueError("Stringsdict must contain a dictionary")
        return values, None
    if path.suffix == ".xcstrings":
        catalog = json.loads(path.read_text(), object_pairs_hook=unique_object)
        if (not isinstance(catalog, dict) or catalog.get("version") != "1.0"
                or not isinstance(catalog.get("strings"), dict)
                or not isinstance(catalog.get("sourceLanguage"), str)):
            raise ValueError("Expected an xcstrings 1.0 catalog with sourceLanguage and strings")
        source = catalog["sourceLanguage"]
        if not re.fullmatch(r"[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)*", source):
            raise ValueError("Invalid catalog sourceLanguage")
        if language and source.replace("_", "-").lower() != language.replace("_", "-").lower():
            raise ValueError("Catalog sourceLanguage must match configured push language")
        return catalog["strings"], source
    raise ValueError("ICU upload accepts .strings, .stringsdict and .xcstrings source files")


# 标准复数类别转换成现有服务端可识别的 ICU plural map。
def convert_forms(forms: dict) -> dict:
    if not isinstance(forms, dict) or "other" not in forms or not set(forms) <= {"zero", "one", "two", "few", "many", "other"}:
        raise ValueError("Plural must contain other and only standard categories")
    return {name: convert_text(value, plural=True) for name, value in forms.items()}


# 只接受独立单变量 stringsdict，signed integer 在导出时统一为 lld。
def convert_stringsdict_entry(entry: dict) -> dict:
    if not isinstance(entry, dict):
        raise ValueError("Plural entry must be a dictionary")
    marker = re.fullmatch(r"%#@([A-Za-z][A-Za-z0-9_]*)@", entry.get("NSStringLocalizedFormatKey", ""))
    if not marker or set(entry) != {"NSStringLocalizedFormatKey", marker[1]}:
        raise ValueError("Only a standalone single-variable plural is supported")
    rule = entry[marker[1]]
    if not isinstance(rule, dict):
        raise ValueError("Plural rule must be a dictionary")
    if (rule.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType"
            or rule.get("NSStringFormatValueTypeKey") not in {"d", "ld", "lld"}):
        raise ValueError("Plural must use NSStringPluralRuleType and signed d, ld or lld")
    return convert_forms({name: value for name, value in rule.items()
                          if name not in {"NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"}})


# 提取 catalog 源语言；不展开 device/substitutions 等会丢失语义的变体。
def convert_catalog_entry(key: str, entry: dict, source: str):
    if not isinstance(entry, dict):
        raise ValueError("Catalog entry must be an object")
    if "shouldTranslate" in entry and not isinstance(entry["shouldTranslate"], bool):
        raise ValueError("shouldTranslate must be a boolean")
    if entry.get("shouldTranslate") is False:
        return None
    localizations = entry.get("localizations", {})
    if not isinstance(localizations, dict):
        raise ValueError("Catalog localizations must be an object")
    # Xcode 省略源 stringUnit 时以 key 作为原文，不能误上传其他语言的译文。
    if source not in localizations:
        return convert_text(key)
    value = localizations[source]
    if not isinstance(value, dict):
        raise ValueError("Source localization must be an object")
    if set(value) == {"stringUnit"}:
        unit = value["stringUnit"]
        if not isinstance(unit, dict) or not isinstance(unit.get("value"), str):
            raise ValueError("stringUnit requires a text value")
        return convert_text(unit["value"])
    if set(value) == {"variations"} and isinstance(value["variations"], dict) and set(value["variations"]) == {"plural"}:
        forms = value["variations"]["plural"]
        if not isinstance(forms, dict):
            raise ValueError("Plural variations must be an object")
        texts = {}
        for name, form in forms.items():
            if not isinstance(form, dict) or set(form) != {"stringUnit"} or not isinstance(form["stringUnit"], dict):
                raise ValueError("Only direct plural stringUnit values are supported")
            texts[name] = form["stringUnit"].get("value")
        return convert_forms(texts)
    raise ValueError("Catalog device/substitutions/mixed variations cannot round-trip through Apple export")


# 每个文件继续扫描所有可解析词条，一次返回全部不兼容项。
def scan_file(path: Path, language: str | None = None) -> tuple[dict, list[dict]]:
    output, issues = {}, []
    try:
        values, source = read_entries(path, language)
    except (ValueError, OSError, UnicodeError, ET.ParseError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        return {}, [{"file": str(path), "key": "", "message": str(error)}]
    for key, entry in values.items():
        try:
            if not isinstance(key, str) or not key:
                raise ValueError("Source keys must be nonempty strings")
            value = (convert_text(entry) if path.suffix == ".strings" else
                     convert_stringsdict_entry(entry) if path.suffix == ".stringsdict" else
                     convert_catalog_entry(key, entry, source))
            if value is not None:
                output[key] = value
        except (ValueError, TypeError) as error:
            issues.append({"file": str(path), "key": key, "message": str(error)})
    return output, issues


# 保留既有单文件转换接口，任何不兼容项都禁止输出部分成功结果。
def convert_file(path: Path, language: str | None = None) -> dict:
    values, issues = scan_file(path, language)
    if issues:
        raise CompatibilityError(issues)
    return values


# 完整检查全部文件及 namespace/language 内重复 key，转换前不访问 CLI 或远端。
def collect_sources(config: dict, config_path: Path) -> tuple[dict, list[dict]]:
    groups, issues = {}, []
    for item in config["push"]["files"]:
        path = (config_path.parent / item["path"]).resolve()
        group = groups.setdefault((item["namespace"], item["language"]), {})
        values, failures = scan_file(path, item["language"])
        issues.extend(dict(issue, namespace=item["namespace"], language=item["language"]) for issue in failures)
        for key in group.keys() & values.keys():
            issues.append({"file": str(path), "key": key, "namespace": item["namespace"],
                           "language": item["language"], "message": "Duplicate key across Apple source files"})
        group.update(values)
    if not groups or any(not values for values in groups.values()) and not issues:
        issues.append({"file": str(config_path), "key": "", "message": "No translatable entries in a configured namespace/language"})
    return groups, issues


# 生成短生命周期配置，保留安全上传策略及 namespace/language 隔离。
def prepare(config_path: Path, directory: Path) -> Path:
    config = json.loads(config_path.read_text())
    push = config["push"]
    groups, issues = collect_sources(config, config_path)
    if issues:
        raise CompatibilityError(issues)
    files = []
    for index, ((namespace, language), values) in enumerate(groups.items()):
        path = directory / f"source-{index}.json"
        path.write_text(json.dumps(values, ensure_ascii=False), encoding="utf-8")
        files.append({"path": str(path), "namespace": namespace, "language": language})
    push["files"] = files
    push["convertPlaceholdersToIcu"] = False
    target = directory / "lingora.json"
    target.write_text(json.dumps(config), encoding="utf-8")
    return target


# 本地检查输出完整诊断；只有显式 push 才要求 CLI 版本并调用远端。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--version")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--report-json", action="store_true", help="Machine-readable source diagnostics; requires --check")
    args = parser.parse_args()
    if args.report_json and not args.check:
        parser.error("--report-json requires --check")
    if args.check:
        config_path = args.config.resolve()
        groups, issues = collect_sources(json.loads(config_path.read_text()), config_path)
        if args.report_json:
            print(json.dumps({"compatibleKeys": sum(map(len, groups.values())), "issues": issues}, ensure_ascii=False))
        else:
            print(f"Checked {len(groups)} namespace/language groups; {len(issues)} compatibility issues")
            if issues:
                print(str(CompatibilityError(issues)))
        raise SystemExit(1 if issues else 0)
    if not args.version or not re.fullmatch(r"\d+\.\d+\.\d+(?:rc\d+)?", args.version):
        parser.error("Push requires a valid pinned --version")
    try:
        with tempfile.TemporaryDirectory(prefix="lingora-icu-") as temporary:
            config = prepare(args.config.resolve(), Path(temporary))
            subprocess.run(["uvx", "--from", f"lingora-cli=={args.version}", "lingora", "--config", str(config), "push"], check=True)
    except CompatibilityError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
