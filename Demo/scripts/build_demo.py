#!/usr/bin/env python3
"""按实际 Xcode 工程配置构建 Demo，并提供隔离的 dev/release Package fixture 验收。"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit

from check_resources import check
from configure_sdk import configure

DEMO = Path(__file__).resolve().parents[1]


# 远端普通构建只消费已提交的同一来源、版本与提交锁，不静默改写解析结果。
def check_resolution(demo: Path, config: dict, *, fixture: bool = False) -> None:
    if config["mode"] == "local":
        return
    path = demo / "LingoraDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    kind = "localSourceControl" if fixture else "remoteSourceControl"
    location = unquote(urlsplit(config["repositoryURL"]).path) if fixture else config["repositoryURL"]
    try:
        pins = json.loads(path.read_text())["pins"]
        valid = (len(pins) == 1 and pins[0].get("kind") == kind
                 and pins[0].get("location") == location
                 and pins[0].get("state", {}).get("version") == config["version"]
                 and re.fullmatch(r"[0-9a-f]{40}", pins[0].get("state", {}).get("revision", "")))
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        valid = False
    if not valid:
        raise ValueError("Missing or mismatched Package.resolved; run build_demo.py --resolve-only and commit the lock file")


# 在临时 Git 仓库中发布真实 SDK 源码 fixture，不修改本仓库或真实版本 Tag。
def package_fixture(root: Path, version: str) -> str:
    source = DEMO.parent / "SDK"
    shutil.copytree(source, root, ignore=shutil.ignore_patterns(".build", ".swiftpm"))
    for args in (
        ["init", "--quiet"], ["add", "."],
        ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
         "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "SDK consumer fixture"],
        ["-c", "tag.gpgsign=false", "tag", version],
    ):
        subprocess.run(["git", "-C", str(root), *args], check=True)
    return root.as_uri()


# 只在临时 Demo 中生成非真实译文，覆盖两个 target 的资源打包流程。
def resource_fixture(demo: Path) -> None:
    for target, namespace in (("LingoraDemo", "app"), ("LingoraCommon", "common")):
        for language in ("ja", "zh-CN"):
            output = demo / target / "Generated/Lingora" / namespace
            output.mkdir(parents=True, exist_ok=True)
            (output / f"{language}.json").write_text(json.dumps({
                "welcome": "Fixture welcome",
                "items_count": {"variations": {"plural": {"other": "%lld items"}}},
            }))


# 统一执行模拟器构建；显式环境 URL 可覆盖 Xcode 项目的开发默认值。
def build(args: argparse.Namespace, workspace: Path) -> None:
    demo = DEMO
    if args.fixture_channel:
        version = "0.0.0-dev.1" if args.fixture_channel == "dev" else "0.0.0"
        url = package_fixture(workspace / "producer", version)
        demo = workspace / "consumer/Demo"
        shutil.copytree(DEMO, demo, ignore=shutil.ignore_patterns(
            "__pycache__", ".build", "DerivedData", "xcuserdata", "Package.resolved", "Generated",
        ))
        configure(demo, {"mode": args.fixture_channel, "version": version,
                         "repositoryURL": url, "localPath": "../nonexistent-sdk"}, fixture=True)
        if (demo.parent / "SDK").exists():
            raise ValueError("Fixture consumer must not contain local SDK")
        resource_fixture(demo)
    config = configure(demo, check=True, fixture=bool(args.fixture_channel))
    command = [
        "xcodebuild", "-project", str(demo / "LingoraDemo.xcodeproj"),
        "-scheme", "LingoraDemo", "-configuration", "Debug",
        "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(workspace / "DerivedData"),
        "-clonedSourcePackagesDirPath", str(workspace / "Packages"),
        "CODE_SIGNING_ALLOWED=NO",
    ]
    delivery = os.environ.get("LINGORA_CONTENT_DELIVERY_URL", "" if args.fixture_channel else None)
    if delivery is not None:
        if delivery.strip():
            parsed = urlsplit(delivery)
            if (parsed.scheme not in ("http", "https") or not parsed.hostname
                    or parsed.username or parsed.password or parsed.query or parsed.fragment
                    or any(c in delivery for c in "\r\n$")):
                raise ValueError("Delivery URL must be public HTTP(S) without query or credentials")
        command.append(f"LINGORA_CONTENT_DELIVERY_URL={delivery.strip()}")
    if args.fixture_channel:
        command.append("LINGORA_SDK_TEST_FIXTURE=1")
    if getattr(args, "resolve_locked", False):
        check_resolution(demo, config)
        if config["mode"] == "local":
            raise ValueError("Locked remote resolution requires dev or release mode")
        lock = demo / "LingoraDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        pins = json.loads(lock.read_text())["pins"]
        command.append("-onlyUsePackageVersionsFromResolvedFile")
        subprocess.run([*command, "-resolvePackageDependencies"], check=True)
        check_resolution(demo, config)
        if json.loads(lock.read_text())["pins"] != pins:
            raise ValueError("Locked resolution changed committed package pins")
        return
    if args.resolve_only or args.fixture_channel:
        subprocess.run([*command, "-resolvePackageDependencies"], check=True)
    check_resolution(demo, config, fixture=bool(args.fixture_channel))
    if args.resolve_only:
        print(f"Verified SDK resolution ({config['mode']}, {config['version'] or 'local'}) and build inputs")
        return
    if config["mode"] != "local":
        command.append("-onlyUsePackageVersionsFromResolvedFile")
    subprocess.run([*command, "build"], check=True)
    app = workspace / "DerivedData/Build/Products/Debug-iphonesimulator/LingoraDemo.app"
    if delivery is not None:
        with (app / "Info.plist").open("rb") as stream:
            if plistlib.load(stream).get("LingoraContentDeliveryURL") != delivery.strip():
                raise ValueError("Built App did not receive the requested Delivery URL")
    if args.fixture_channel or args.check_resources:
        resource_config = Path(args.config).resolve() if args.config else demo / "ci/lingora.dev.json"
        check(resource_config, {"app": demo / "LingoraDemo/Generated",
                       "common": demo / "LingoraCommon/Generated"}, app)
    if args.artifact:
        destination = Path(args.artifact).resolve()
        if destination.exists():
            raise ValueError("Artifact destination already exists; use a fresh path")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(app, destination)
    if args.fixture_channel:
        # 精确版本不存在时必须让 SwiftPM 失败，不能复用刚构建的版本或回退源码。
        missing_version = "99.0.0-dev.1" if args.fixture_channel == "dev" else "99.0.0"
        configure(demo, {"version": missing_version}, fixture=True)
        result = subprocess.run([*(item for item in command if item != "-onlyUsePackageVersionsFromResolvedFile"),
                                 "-resolvePackageDependencies"],
                                capture_output=True, text=True)
        if result.returncode == 0 or missing_version not in result.stdout + result.stderr:
            raise ValueError("Missing exact version did not fail as expected: "
                             + result.stdout[-2000:] + result.stderr[-2000:])
        print(f"Verified missing {args.fixture_channel} version is rejected without source fallback")
    print(f"Verified Demo ({config['mode']}, {config['version'] or 'local'}); App and framework compiled against Lingora")


# 临时工程与解析缓存随命令结束清理，只保留显式请求的模拟器产物。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-channel", choices=("dev", "release"),
                        help="Test-only: build a temporary Git package in an isolated consumer")
    parser.add_argument("--check-resources", action="store_true")
    parser.add_argument("--config")
    parser.add_argument("--resolve-locked", action="store_true", help="Resolve only the committed remote lock before CI writes")
    parser.add_argument("--resolve-only", action="store_true",
                        help="Explicitly resolve a changed SDK source/version before building and commit Package.resolved")
    parser.add_argument("--artifact", help="New destination for the simulator .app")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="lingora-consumer-") as directory:
        build(args, Path(directory))


if __name__ == "__main__":
    main()
