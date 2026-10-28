"""验证通用工具支持任意 namespace/Bundle，且失败前不会写远端。"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from sync_translations import load_resources, synchronize
from check_resources import check


class SyncTranslationsTests(unittest.TestCase):
    """使用三组自定义 namespace 和嵌套 Bundle，避免依赖 Demo 的 app/common 特例。"""

    # 创建最小 ICU 输入配置与独立生成目录。
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'lingora.json'
        self.resources = self.root / 'resources.json'
        self.version = self.root / 'cli.version'
        self.version.write_text('0.1.0rc4')
        self.config.write_text(json.dumps({'push': {'files': [
            {'namespace': name, 'language': 'en', 'path': f'{name}.strings'}
            for name in ('checkout', 'profile', 'settings')]}, 'pull': {
                'format': 'apple-sdk', 'fileStructureTemplate': 'Lingora/{namespace}/{languageTag}.{extension}',
                'languages': ['ja']}}))
        self.resources.write_text(json.dumps({name: {'output': f'Generated/{name}', 'bundle': bundle}
                                             for name, bundle in [('checkout', '.'),
                                                                  ('profile', 'Frameworks/Profile.framework'),
                                                                  ('settings', 'Settings.bundle')]}))

    # 模拟 CLI 输出真实 JSON，以便最终资源检查仍执行。
    def run_cli(self, command, **kwargs):
        if 'pull' in command:
            namespace = command[command.index('--namespaces') + 1]
            output = Path(command[command.index('--path') + 1]) / 'Lingora' / namespace / 'ja.json'
            output.parent.mkdir(parents=True)
            output.write_text('{"hello":"翻訳"}')
        return subprocess.CompletedProcess(command, 0)

    # 多 namespace 仍严格执行所有 validate、一次 push、所有 pull、所有 validate。
    def test_generic_order_and_bundle_mapping(self):
        with patch('sync_translations.prepare', return_value=self.config), \
             patch('sync_translations.subprocess.run', side_effect=self.run_cli) as run:
            synchronize(self.config, self.resources, self.version)
        self.assertEqual([call.args[0][6] for call in run.call_args_list],
                         ['validate'] * 3 + ['push'] + ['pull'] * 3 + ['validate'] * 3)
        outputs, bundles = load_resources(self.resources)
        app = self.root / 'App.app'
        for namespace, output in outputs.items():
            relative = Path(f'Lingora/{namespace}/ja.json')
            target = app / bundles[namespace] / relative
            target.parent.mkdir(parents=True)
            target.write_bytes((output / relative).read_bytes())
        check(self.config, outputs, app, bundle_paths=bundles)
        (app / 'Settings.bundle/Lingora/settings/ja.json').write_text('{"hello":"Wrong"}')
        with self.assertRaisesRegex(ValueError, 'differs'):
            check(self.config, outputs, app, bundle_paths=bundles)

    # ICU 转换、validate 和 push 失败都停止后续远端操作。
    def test_failures_stop_pipeline(self):
        with patch('sync_translations.prepare', side_effect=ValueError('Unsupported format')), \
             patch('sync_translations.subprocess.run') as run:
            with self.assertRaises(ValueError):
                synchronize(self.config, self.resources, self.version)
            run.assert_not_called()
        for failing in ('validate', 'push', 'pull'):
            calls = []
            def fail(command, **kwargs):
                calls.append(command[6])
                if command[6] == failing:
                    raise subprocess.CalledProcessError(1, command)
            with patch('sync_translations.prepare', return_value=self.config), \
                 patch('sync_translations.subprocess.run', side_effect=fail):
                with self.assertRaises(subprocess.CalledProcessError):
                    synchronize(self.config, self.resources, self.version)
            self.assertEqual(calls[-1], failing)
            self.assertEqual(calls.count(failing), 1)

    # 危险或重叠目录、无效格式和未知 namespace 在 CLI 执行前失败。
    def test_invalid_mapping_and_config_fail_before_cli(self):
        for mapping in [{'checkout': {'output': '.', 'bundle': '.'}},
                        {'checkout': {'output': 'Generated', 'bundle': '../escape'}},
                        {'checkout': {'output': 'Generated', 'bundle': '.'},
                         'profile': {'output': 'Generated/sub', 'bundle': '.'}}]:
            self.resources.write_text(json.dumps(mapping))
            with patch('sync_translations.subprocess.run') as run:
                with self.assertRaises(ValueError):
                    synchronize(self.config, self.resources, self.version)
                run.assert_not_called()
