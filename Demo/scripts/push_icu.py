"""将受支持的 Apple 基础资源转为 ICU JSON，再调用固定版本的公开 CLI。"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
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
        match = re.match(r"%(?:%|(?:1\$)?(?:@|lld))", text[cursor:])
        if not match:
            raise ValueError("Only a single %@ or %lld parameter is supported; width/precision/reordering are rejected")
        token = match.group()
        cursor += len(token)
        if token == "%%":
            result.append("%")
            continue
        parameters += 1
        if parameters > 1 or (plural and token.endswith("@")):
            raise ValueError("Apple export cannot preserve multiple parameters or plural object arguments")
        result.append("#" if plural else "{arg1, number}" if token.endswith("lld") else "{arg1}")
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


# 合并普通文本与单变量 plural，任何不支持的结构都在远端写入前失败。
def convert_file(path: Path) -> dict:
    if path.suffix == ".strings":
        values = read_strings(path)
        if not all(isinstance(key, str) and key and isinstance(value, str) for key, value in values.items()):
            raise ValueError("Apple strings must contain nonempty keys and text values")
        output = {}
        for key, value in values.items():
            try:
                output[key] = convert_text(value)
            except ValueError as error:
                raise ValueError(f"{path.name}, key {key}: {error}") from error
        return output
    if path.suffix != ".stringsdict":
        raise ValueError("ICU upload accepts only .strings and .stringsdict source files")
    data = path.read_bytes()
    document = ET.fromstring(data)
    for dictionary in document.iter("dict"):
        keys = [key.text for key in dictionary.findall("key")]
        if len(keys) != len(set(keys)):
            raise ValueError(f"Duplicate key in {path.name}")
    values = plistlib.loads(data)
    if not isinstance(values, dict):
        raise ValueError("Stringsdict must contain a dictionary")
    output = {}
    for key, entry in values.items():
        if not key or not isinstance(entry, dict):
            raise ValueError("Plural entries require a nonempty key and dictionary")
        marker = re.fullmatch(r"%#@([A-Za-z][A-Za-z0-9_]*)@", entry.get("NSStringLocalizedFormatKey", ""))
        if not marker or set(entry) != {"NSStringLocalizedFormatKey", marker[1]}:
            raise ValueError("Only a standalone single-variable plural is supported")
        rule = entry[marker[1]]
        if not isinstance(rule, dict):
            raise ValueError("Plural rule must be a dictionary")
        if rule.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType" or rule.get("NSStringFormatValueTypeKey") != "lld":
            raise ValueError("Plural must use NSStringPluralRuleType and lld")
        forms = {name: value for name, value in rule.items() if name not in {"NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"}}
        if "other" not in forms or not set(forms) <= {"zero", "one", "two", "few", "many", "other"}:
            raise ValueError("Plural must contain other and only standard categories")
        # JSON plural map 被现有导入器识别为 PLURAL，正文中的 # 保留计数语义。
        try:
            output[key] = {name: convert_text(value, plural=True) for name, value in forms.items()}
        except ValueError as error:
            raise ValueError(f"{path.name}, key {key}: {error}") from error
    return output


# 生成短生命周期配置，保留安全上传策略及 namespace/language 隔离。
def prepare(config_path: Path, directory: Path) -> Path:
    config = json.loads(config_path.read_text())
    push = config["push"]
    groups = {}
    for item in push["files"]:
        group = groups.setdefault((item["namespace"], item["language"]), {})
        values = convert_file((config_path.parent / item["path"]).resolve())
        if group.keys() & values.keys():
            raise ValueError("Duplicate key across Apple source files")
        group.update(values)
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


# 普通检查只生成并校验临时输入；显式 push 才调用 CLI，不打印配置或密钥。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:rc\d+)?", args.version):
        parser.error("Invalid pinned CLI version")
    with tempfile.TemporaryDirectory(prefix="lingora-icu-") as temporary:
        config = prepare(args.config.resolve(), Path(temporary))
        if not args.check:
            subprocess.run(["uvx", "--from", f"lingora-cli=={args.version}", "lingora", "--config", str(config), "push"], check=True)


if __name__ == "__main__":
    main()
