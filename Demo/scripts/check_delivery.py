#!/usr/bin/env python3
"""使用精确远程 SDK 验收真实 CDN 或实际产物的离线 Bundle JSON。"""
import argparse
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit
from urllib.request import urlopen

from check_resources import read_resource

from build_demo import check_resolution
from configure_sdk import configure

DEMO = Path(__file__).resolve().parents[1]


# 运行公开 API 探针；不读取 API Key，也不向翻译平台写入。
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-bundle", type=Path, help="Verify packaged JSON offline instead of CDN")
    args = parser.parse_args()
    config = configure(DEMO, check=True)
    if config['mode'] == 'local':
        raise ValueError('Delivery verification requires a published SDK')
    check_resolution(DEMO, config)
    url = 'https://bundled-probe.invalid' if args.app_bundle else os.environ.get('LINGORA_CONTENT_DELIVERY_URL', '')
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or any(c.isspace() for c in url)):
        raise ValueError('Provide a credential-free HTTPS Content Delivery URL')
    identity = urlsplit(config['repositoryURL']).path.rsplit('/', 1)[-1].removesuffix('.git').lower()
    with tempfile.TemporaryDirectory(prefix='lingora-delivery-') as directory:
        root = Path(directory)
        (root / 'Sources/DeliveryProbe').mkdir(parents=True)
        (root / 'Package.swift').write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DeliveryProbe", platforms: [.macOS(.v13)],
    dependencies: [.package(url: {json.dumps(config['repositoryURL'])}, exact: {json.dumps(config['version'])})],
    targets: [.executableTarget(name: "DeliveryProbe", dependencies: [
        .product(name: "Lingora", package: {json.dumps(identity)})])])
''')
        source = 'BundledProbe.swift' if args.app_bundle else 'DeliveryProbe.swift'
        shutil.copy(DEMO / 'tests' / source, root / 'Sources/DeliveryProbe/Probe.swift')
        shutil.copy(DEMO / 'LingoraDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved', root)
        env = {key: value for key, value in os.environ.items() if key != 'LINGORA_API_KEY'}
        subprocess.run(['swift', 'run', '--package-path', str(root), '--force-resolved-versions',
                        'DeliveryProbe', str(args.app_bundle.resolve()) if args.app_bundle else url], env=env, check=True, timeout=600)

        if not args.app_bundle:
            # 公开 CDN 只读验收同时覆盖离线 JSON，不需要 Secret 或 CLI 写入。
            app = root / "Offline.app"
            for namespace in ("app", "common"):
                bundle = app if namespace == "app" else app / "Frameworks/LingoraCommon.framework"
                resources = bundle / "Lingora" / namespace
                resources.mkdir(parents=True)
                (bundle / "Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleIdentifier": f"io.lingora.probe.{namespace}",
                    "CFBundleDevelopmentRegion": "en",
                }))
                for language in ("ja", "zh-CN"):
                    with urlopen(f"{url.rstrip('/')}/{namespace}/{language}.json", timeout=30) as response:
                        data = response.read(10 * 1024 * 1024 + 1)
                    destination = resources / f"{language}.json"
                    destination.write_bytes(data)
                    read_resource(destination)
            shutil.copy(DEMO / 'tests/BundledProbe.swift', root / 'Sources/DeliveryProbe/Probe.swift')
            subprocess.run(['swift', 'run', '--package-path', str(root), '--force-resolved-versions',
                            'DeliveryProbe', str(app)], env=env, check=True, timeout=600)


if __name__ == '__main__':
    main()
