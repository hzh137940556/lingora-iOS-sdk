"""通过资源映射串行执行 iOS 翻译同步；无需复制或修改工具源码。"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from check_resources import check
from push_icu import prepare


# namespace、输出目录和 Bundle 归属由业务配置提供，路径相对映射文件。
def load_resources(path: Path) -> tuple[dict[str, Path], dict[str, Path]]:
    entries = json.loads(path.read_text())
    if not isinstance(entries, dict) or not entries:
        raise ValueError('Resource mapping must contain at least one namespace')
    outputs, bundles = {}, {}
    for namespace, item in entries.items():
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', namespace):
            raise ValueError('Invalid namespace')
        if not isinstance(item, dict) or set(item) != {'output', 'bundle'}:
            raise ValueError('Each namespace requires output and bundle')
        if not all(isinstance(value, str) and value.strip() for value in item.values()):
            raise ValueError('Resource paths must be nonempty strings')
        output = (path.parent / item['output']).resolve()
        bundle = Path(item['bundle'])
        if bundle.is_absolute() or '..' in bundle.parts:
            raise ValueError('Bundle path must stay inside the built App')
        if output == path.parent.resolve() or output in path.resolve().parents:
            raise ValueError('Generated output must use a dedicated directory')
        if any(output == old or output in old.parents or old in output.parents for old in outputs.values()):
            raise ValueError('Generated output directories must not overlap')
        outputs[namespace], bundles[namespace] = output, bundle
    return outputs, bundles


# 任何输入或转换错误在写远端前失败；子命令失败即停止，不删除历史资源。
def synchronize(config: Path, resources: Path, version_file: Path) -> None:
    outputs, bundles = load_resources(resources)
    version = version_file.read_text().strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:rc\d+)?', version):
        raise ValueError('Invalid pinned CLI version')
    settings = json.loads(config.read_text())
    pull = settings['pull']
    if (pull.get('format') != 'apple-sdk'
            or pull.get('fileStructureTemplate') != 'Lingora/{namespace}/{languageTag}.{extension}'
            or not isinstance(pull.get('languages'), list) or not pull['languages']
            or not all(isinstance(tag, str) and re.fullmatch(r'[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*', tag)
                       for tag in pull['languages'])):
        raise ValueError('Configure namespaced Apple SDK output and explicit languages')
    if {item['namespace'] for item in settings['push']['files']} != set(outputs):
        raise ValueError('Source namespaces must match resource mapping')
    sources = [(config.parent / item['path']).resolve() for item in settings['push']['files']]
    if any(output == source or output in source.parents for output in outputs.values() for source in sources):
        raise ValueError('Generated output must not contain source resources')
    cli = ['uvx', '--from', f'lingora-cli=={version}', 'lingora']
    with tempfile.TemporaryDirectory(prefix='lingora-icu-') as temporary:
        prepared = prepare(config, Path(temporary))
        for namespace, output in outputs.items():
            subprocess.run([*cli, '--config', str(config), 'validate', '--namespaces', namespace, '--path', str(output)], check=True)
        subprocess.run([*cli, '--config', str(prepared), 'push'], check=True)
        for operation in ('pull', 'validate'):
            for namespace, output in outputs.items():
                subprocess.run([*cli, '--config', str(config), operation, '--namespaces', namespace, '--path', str(output)], check=True)
        check(config, outputs, bundle_paths=bundles)


# check-only 仅检查资源及其打包归属，不访问 CLI 或远端。
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--resources', type=Path, required=True)
    parser.add_argument('--version-file', type=Path, default=Path('lingora-cli.version'))
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--app-bundle', type=Path)
    args = parser.parse_args()
    if args.check_only:
        outputs, bundles = load_resources(args.resources.resolve())
        check(args.config.resolve(), outputs, args.app_bundle, bundle_paths=bundles)
    else:
        if args.app_bundle:
            parser.error('--app-bundle requires --check-only')
        synchronize(args.config.resolve(), args.resources.resolve(), args.version_file.resolve())


if __name__ == '__main__':
    main()
