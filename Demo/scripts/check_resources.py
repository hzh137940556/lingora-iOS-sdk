#!/usr/bin/env python3
"""检查必需 Apple 资源，并可核对它们是否完整进入各自 Bundle。"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess


# 使用系统解析器同时支持文本和编译后的 binary plist 资源。
def read_resource(path: Path) -> dict:
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    value = json.loads(result.stdout)
    if not isinstance(value, dict) or not value:
        raise ValueError(f"Empty Apple resource: {path}")
    if path.suffix == ".strings":
        if not all(isinstance(v, str) and v.strip() for v in value.values()):
            raise ValueError(f"Empty or invalid string: {path}")
    else:
        for entry in value.values():
            if not isinstance(entry, dict) or not entry.get("NSStringLocalizedFormatKey"):
                raise ValueError(f"Invalid plural: {path}")
            variables = [v for v in entry.values() if isinstance(v, dict)]
            if not variables or any(
                v.get("NSStringFormatSpecTypeKey") != "NSStringPluralRuleType"
                or not v.get("NSStringFormatValueTypeKey")
                or not isinstance(v.get("other"), str) or not v["other"].strip()
                for v in variables
            ):
                raise ValueError(f"Missing plural other/type: {path}")
    return value


# 根据配置的目标语言检查两个 namespace；目录由调用方显式传入。
def check(config: Path, outputs: dict[str, Path], app_bundle: Path | None = None) -> None:
    languages = json.loads(config.read_text())["pull"]["languages"]
    if not isinstance(languages, list) or not languages:
        raise ValueError("Configure nonempty pull.languages")
    for language in languages:
        if not isinstance(language, str) or not re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", language):
            raise ValueError("Unsafe language tag")
        for namespace, output in outputs.items():
            bundle = app_bundle
            if bundle is not None and namespace == "common":
                bundle = bundle / "Frameworks/LingoraCommon.framework"
            for extension in ("strings", "stringsdict"):
                relative = Path(f"{language}.lproj/{namespace}.{extension}")
                expected = read_resource(output / relative)
                if bundle is not None and read_resource(bundle / relative) != expected:
                    raise ValueError(f"Packaged resource differs: {bundle / relative}")
    print(f"Verified {len(languages) * len(outputs) * 2} required Apple resource files")


# 提供 CLI 同步和构建后共用的本地检查入口。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--app-output", type=Path, required=True)
    parser.add_argument("--common-output", type=Path, required=True)
    parser.add_argument("--app-bundle", type=Path)
    args = parser.parse_args()
    check(args.config, {"app": args.app_output, "common": args.common_output}, args.app_bundle)


if __name__ == "__main__":
    main()
