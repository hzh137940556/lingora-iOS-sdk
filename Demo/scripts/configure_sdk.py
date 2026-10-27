#!/usr/bin/env python3
"""将 SDK 来源配置同步到实际 Xcode 工程，供 IDE、命令行与 CI 共用。"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import urlsplit

DEMO = Path(__file__).resolve().parents[1]
REFERENCE = "800000000000000000000001"
STABLE = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"


# 渠道使用互斥版本格式；远端模式完全不读取 localPath 或本地 SDK。
def validate(config: dict, demo: Path, *, fixture: bool = False, check_local: bool = True) -> None:
    if set(config) != {"mode", "version", "repositoryURL", "localPath"}:
        raise ValueError("SDK config must contain mode, version, repositoryURL and localPath")
    mode = config["mode"]
    if mode == "local":
        path = config["localPath"]
        if not isinstance(path, str) or not path.strip() or Path(path).is_absolute():
            raise ValueError("localPath must be a nonempty path relative to Demo")
        if any(character in path for character in "\n\r$"):
            raise ValueError("localPath must not contain build variables or newlines")
        if check_local and not (demo / path / "Package.swift").is_file():
            raise ValueError("Local SDK Package.swift not found; fix localPath")
        if config["version"] != "":
            raise ValueError("Local mode does not use a version; set version to empty")
        return
    if mode not in ("dev", "release"):
        raise ValueError("SDK mode must be local, dev or release")
    pattern = STABLE + (r"-dev\.(0|[1-9][0-9]*)" if mode == "dev" else "")
    if not isinstance(config["version"], str) or not re.fullmatch(pattern, config["version"]):
        raise ValueError(f"{mode} requires an exact " + ("X.Y.Z-dev.N" if mode == "dev" else "X.Y.Z"))
    url = config["repositoryURL"]
    if not isinstance(url, str):
        raise ValueError("repositoryURL must be a string")
    parsed = urlsplit(url)
    if fixture and parsed.scheme == "file":
        return
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or any(c in url for c in "\n\r$")):
        raise ValueError("repositoryURL must be credential-free HTTPS")


# 精确替换单个已知 Package 引用，保留其余工程配置及两个 target 的 product 关联。
def render_project(text: str, config: dict) -> str:
    kind = "XCLocalSwiftPackageReference" if config["mode"] == "local" else "XCRemoteSwiftPackageReference"
    if config["mode"] == "local":
        fields = f"\t\t\trelativePath = {json.dumps(config['localPath'], ensure_ascii=False)};\n"
    else:
        fields = (f"\t\t\trepositoryURL = {json.dumps(config['repositoryURL'], ensure_ascii=False)};\n"
                  "\t\t\trequirement = {\n\t\t\t\tkind = exactVersion;\n"
                  f"\t\t\t\tversion = {json.dumps(config['version'])};\n\t\t\t}};\n")
    replacement = f"\t\t{REFERENCE} /* Lingora SDK */ = {{\n\t\t\tisa = {kind};\n{fields}\t\t}};"
    pattern = rf"^\t\t{REFERENCE} /\*[^\n]*\*/ = \{{\n.*?^\t\t\}};"
    result, count = re.subn(pattern, lambda _: replacement, text, flags=re.MULTILINE | re.DOTALL)
    if count != 1 or len(re.findall(r"isa = XC(?:Local|Remote)SwiftPackageReference;", text)) != 1:
        raise ValueError("Expected exactly one Lingora SDK package reference")
    result = re.sub(rf"{REFERENCE} /\*[^\n]*?\*/", f"{REFERENCE} /* Lingora SDK */", result)
    result = re.sub(r"XC(?:Local|Remote)SwiftPackageReference section", f"{kind} section", result)
    return result


# 原子替换单个文件；配置与工程不一致时检查命令和 Xcode 构建会拒绝继续。
def write_atomic(path: Path, text: str) -> None:
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False, encoding="utf-8") as stream:
        temporary = Path(stream.name)
        stream.write(text)
    try:
        temporary.chmod(path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


# 保存或检查同一份配置；测试 fixture 的 file URL 只通过内部参数开放。
def configure(demo: Path, overrides: dict | None = None, *, check: bool = False, fixture: bool = False) -> dict:
    path = demo / "sdk-source.json"
    config = json.loads(path.read_text())
    if not isinstance(config, dict):
        raise ValueError("SDK configuration must be a JSON object")
    config.update(overrides or {})
    validate(config, demo, fixture=fixture, check_local=not check)
    project = demo / "LingoraDemo.xcodeproj/project.pbxproj"
    current = project.read_text()
    expected = render_project(current, config)
    if check:
        if current != expected:
            raise ValueError("SDK config/project mismatch; close Xcode and run make configure-sdk")
    else:
        if expected != current:
            write_atomic(project, expected)
        serialized = json.dumps(config, indent=2, ensure_ascii=False) + "\n"
        if serialized != path.read_text():
            write_atomic(path, serialized)
    return config


# 配置参数会持久化，普通构建和 Xcode 不再单独选择隐藏的 SDK 来源。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("local", "dev", "release"))
    parser.add_argument("--version")
    parser.add_argument("--repository-url")
    parser.add_argument("--local-path")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    overrides = {key: value for key, value in {
        "mode": args.mode, "version": args.version,
        "repositoryURL": args.repository_url, "localPath": args.local_path,
    }.items() if value is not None}
    if args.check and overrides:
        parser.error("--check cannot override configuration")
    if args.mode == "local" and args.version is None:
        overrides["version"] = ""
    try:
        config = configure(DEMO, overrides, check=args.check,
                           fixture=args.check and os.environ.get("LINGORA_SDK_TEST_FIXTURE") == "1")
    except (ValueError, OSError) as error:
        parser.exit(1, f"SDK configuration error: {error}\n")
    print(f"SDK mode={config['mode']}, version={config['version'] or '(local)'}, project synchronized")


if __name__ == "__main__":
    main()
