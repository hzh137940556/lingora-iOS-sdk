#!/usr/bin/env python3
"""在无 Demo、无本地 SDK 依赖的消费者中验收精确 Swift Package 版本。"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit

from sdk_release import Release

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/hzh137940556/lingora-iOS-sdk.git"


# 生产验收只接受无凭据的公开 HTTPS 仓库，测试 file URL 仅在内部创建。
def validate_repository(url: str) -> None:
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or any(c in url for c in "\n\r")):
        raise ValueError("Package repository must be credential-free HTTPS")


# 从真实 SDK 目录创建临时源码包，不修改工作仓库或真实版本 Tag。
def fixture_repository(path: Path, release: Release) -> str:
    shutil.copytree(ROOT / "SDK", path, ignore=shutil.ignore_patterns(".build", ".swiftpm"))
    for args in (
        ["init", "--quiet"], ["add", "."],
        ["-c", "user.name=Package Test", "-c", "user.email=package-test@example.invalid",
         "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Package fixture"],
        ["-c", "tag.gpgsign=false", "tag", release.version],
    ):
        subprocess.run(["git", "-C", str(path), *args], check=True)
    return path.as_uri()


# 生成仅引用远端精确版本的独立 library，不包含 .package(path:) 或 SDK 源码副本。
def write_consumer(path: Path, repository: str, version: str) -> None:
    identity = urlsplit(repository).path.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git").lower()
    source = path / "Sources/PackageProbe"
    source.mkdir(parents=True)
    (path / "Package.swift").write_text(f'''// swift-tools-version: 6.0
// 验证发布包的 product 和公开 API 可以由独立 Swift Package 使用。
import PackageDescription
let package = Package(
    name: "PackageProbe",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [.package(url: {json.dumps(repository)}, exact: {json.dumps(version)})],
    targets: [.target(name: "PackageProbe", dependencies: [
        .product(name: "Lingora", package: {json.dumps(identity)})
    ])]
)
''')
    (source / "PackageProbe.swift").write_text('''// 编译真实公开 API，避免仅验收一个空 Package。
import Foundation
import Lingora

/// 验证调用方可以读取翻译并创建响应式 SwiftUI 文本。
@MainActor
public func packageProbe() -> LingoraText {
    _ = Lingora.shared.translate("welcome", table: "app")
    return LingoraText("welcome", table: "app")
}
''')


# 验收宿主和 iOS Simulator 编译，并检查解析结果确实为指定版本。
def verify(repository: str, release: Release, workspace: Path) -> None:
    consumer = workspace / "consumer"
    write_consumer(consumer, repository, release.version)
    subprocess.run(["swift", "build", "--package-path", str(consumer)], check=True)
    pins = json.loads((consumer / "Package.resolved").read_text())["pins"]
    if len(pins) != 1 or pins[0]["state"].get("version") != release.version:
        raise ValueError("Consumer did not resolve the exact requested SDK version")
    checkouts = list((consumer / ".build/checkouts").iterdir())
    if len(checkouts) != 1 or not (checkouts[0] / "Package.swift").is_file():
        raise ValueError("Expected one package-root SDK checkout")
    if any((checkouts[0] / name).exists() for name in ("SDK", "Demo", "scripts")):
        raise ValueError("Published package contains repository-only directories")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    subprocess.run([
        "swift", "build", "--package-path", str(consumer),
        "--triple", "arm64-apple-ios16.0-simulator", "--sdk", sdk,
    ], check=True)
    print(f"Verified Swift Package {release.version}: exact resolution, public API, macOS and iOS Simulator")


# 本地 fixture 与真实已发布包共用验收路径；默认不创建或上传任何版本。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--channel", choices=("dev", "release"), required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--fixture", action="store_true", help="Test-only temporary package from SDK/")
    args = parser.parse_args()
    release = Release(args.channel, args.version)
    validate_repository(args.repository)
    with tempfile.TemporaryDirectory(prefix="lingora-package-") as directory:
        workspace = Path(directory)
        repository = fixture_repository(workspace / "sdk-package", release) if args.fixture else args.repository
        verify(repository, release, workspace)


if __name__ == "__main__":
    main()
