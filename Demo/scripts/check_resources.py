#!/usr/bin/env python3
"""检查必需 Apple 资源，并可核对它们是否完整进入各自 Bundle。"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


# 严格检查 SDK JSON 形状，避免不可解析的翻译进入 App 或 framework。
def read_resource(path: Path) -> dict:
    if path.stat().st_size > 10 * 1024 * 1024:
        raise ValueError(f"Oversized Apple SDK resource: {path}")
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or not value:
        raise ValueError(f"Empty Apple SDK resource: {path}")
    for key, entry in value.items():
        if not key:
            raise ValueError(f"Empty translation key: {path}")
        if isinstance(entry, str) and entry.strip():
            continue
        if not isinstance(entry, dict) or set(entry) != {"variations"}:
            raise ValueError(f"Invalid Apple SDK entry: {path}")
        variations = entry["variations"]
        if not isinstance(variations, dict) or set(variations) != {"plural"}:
            raise ValueError(f"Invalid Apple SDK variations: {path}")
        forms = variations["plural"]
        if (not isinstance(forms, dict) or "other" not in forms
                or not set(forms).issubset({"zero", "one", "two", "few", "many", "other"})
                or not all(isinstance(text, str) and text.strip() for text in forms.values())):
            raise ValueError(f"Invalid Apple SDK plural: {path}")
    return value


# 根据配置的目标语言检查两个 namespace；目录由调用方显式传入。
def check(config: Path, outputs: dict[str, Path], app_bundle: Path | None = None) -> None:
    pull = json.loads(config.read_text())["pull"]
    if (pull.get("format") != "apple-sdk"
            or pull.get("fileStructureTemplate") != "Lingora/{namespace}/{languageTag}.{extension}"):
        raise ValueError("Demo requires namespaced Apple SDK JSON layout")
    languages = pull["languages"]
    if not isinstance(languages, list) or not languages:
        raise ValueError("Configure nonempty pull.languages")
    for language in languages:
        if not isinstance(language, str) or not re.fullmatch(r"[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", language):
            raise ValueError("Unsafe language tag")
        for namespace, output in outputs.items():
            bundle = app_bundle
            if bundle is not None and namespace == "common":
                bundle = bundle / "Frameworks/LingoraCommon.framework"
            relative = Path(f"Lingora/{namespace}/{language}.json")
            expected = read_resource(output / relative)
            if bundle is not None and read_resource(bundle / relative) != expected:
                raise ValueError(f"Packaged resource differs: {bundle / relative}")
    print(f"Verified {len(languages) * len(outputs)} required Apple SDK JSON files")


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
