#!/usr/bin/env python3
"""使用精确远程 SDK 在无 Bundle 翻译的消费者中验收真实 CDN。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit

from build_demo import check_resolution
from configure_sdk import configure

DEMO = Path(__file__).resolve().parents[1]


# 运行公开 API 探针；不读取 API Key，也不向翻译平台写入。
def main():
    config = configure(DEMO, check=True)
    if config['mode'] == 'local':
        raise ValueError('Delivery verification requires a published SDK')
    check_resolution(DEMO, config)
    url = os.environ.get('LINGORA_CONTENT_DELIVERY_URL', '')
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
        shutil.copy(DEMO / 'tests/DeliveryProbe.swift', root / 'Sources/DeliveryProbe/Probe.swift')
        shutil.copy(DEMO / 'LingoraDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved', root)
        env = {key: value for key, value in os.environ.items() if key != 'LINGORA_API_KEY'}
        subprocess.run(['swift', 'run', '--package-path', str(root), '--force-resolved-versions',
                        'DeliveryProbe', url], env=env, check=True, timeout=600)


if __name__ == '__main__':
    main()
