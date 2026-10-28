"""从固定 CLDR 49 cardinal 数据生成 Swift 规则与可用 Double 样例；构建时不联网。"""
import argparse
from decimal import Decimal
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'scripts/cldr/plurals.xml'


# 将 CLDR 整数集合关系转换为受限 Swift 表达式，未知语法直接拒绝。
def relation(text):
    match = re.fullmatch(r'([nivwftce])(?: % (\d+))? (!=|=) ([\d.,]+)', text)
    if not match:
        raise ValueError(f'Unsupported CLDR expression: {text}')
    operand, modulus, operator, values = match.groups()
    value = f'o.{operand}'
    if modulus:
        if operand in ('f', 't'):
            value = f'Double(o.fractionValue % {modulus})'
        else:
            value += f'.truncatingRemainder(dividingBy: {modulus})'
    ranges = []
    for item in values.split(','):
        bounds = item.split('..')
        ranges.append(f'{bounds[0]}...{bounds[-1]}')
    expression = f'matches({value}, [{", ".join(ranges)}])'
    return ('!' if operator == '!=' else '') + expression


# 保留 CLDR 的 and 优先于 or，避免依靠生成器外的表达式解释器。
def condition(text):
    return ' || '.join('(' + ' && '.join(relation(part) for part in group.split(' and ')) + ')'
                       for group in text.split(' or '))


# 抽取官方样例端点；Double API 无法保留可见尾零或 compact 指数，因此排除这两类。
def samples(text):
    for section in re.split(r'@integer|@decimal', text)[1:]:
        for sample in section.strip().split(','):
            for value in sample.strip().split('~'):
                if not re.fullmatch(r'\d+(?:\.\d+)?', value):
                    continue
                if '.' in value and value.endswith('0'):
                    continue
                if Decimal(value) >= Decimal(2**53):
                    continue
                yield value


# 输出可审阅的分组规则及直接来自官方数据的期望值。
def generate():
    groups = ET.parse(SOURCE).findall('./plurals/pluralRules')
    code = ['// 由 scripts/generate_plural_rules.py 从 Unicode CLDR 49 生成；勿手工编辑。',
            '// 数据许可见 THIRD_PARTY_NOTICES.md。', 'import Foundation', '',
            'extension PluralRules {', '    /// 按完整标签优先、基础语言其次选择 CLDR cardinal 规则。',
            '    static func generatedCategory(_ o: Operands, tag: String) -> String? {', '        switch tag {']
    tests = ['// 由 CLDR 49 官方普通数值样例生成；compact 和可见尾零不属于 Double API。',
             'import XCTest', '@testable import Lingora', '',
             'final class CLDRSampleTests: XCTestCase {']
    for index, group in enumerate(groups):
        tags = group.attrib['locales'].split()
        code.append('        case ' + ', '.join('"' + tag.lower().replace('_', '-') + '"' for tag in tags) + ':')
        cases = []
        for rule in group:
            text = rule.text or ''
            category = rule.attrib['count']
            expression = text.split('@')[0].strip()
            if expression:
                code.append(f'            if {condition(expression)} {{ return "{category}" }}')
            for value in samples(text):
                cases.append(f'            ({value}, "{category}")')
        code.append('            return "other"')
        tests += ['    /// 验证该规则组所有 locale 的官方样例，独立于生成的判断表达式。',
                  f'    func testGroup{index}() {{',
                  '        let cases: [(Double, String)] = [', ',\n'.join(sorted(set(cases))), '        ]',
                  '        for tag in [' + ', '.join('"'+tag.replace('_','-')+'"' for tag in tags) + '] {',
                  '            for (value, expected) in cases {',
                  '                XCTAssertEqual(PluralRules.category(for: value, locale: Locale(identifier: tag)), expected, "\\(tag): \\(value)")',
                  '            }', '        }', '    }']
    code += ['        default: return nil', '        }', '    }', '}', '']
    tests += ['}', '']
    return {ROOT/'SDK/Sources/Lingora/CLDRPluralRules.swift': '\n'.join(code),
            ROOT/'SDK/Tests/LingoraTests/CLDRSampleTests.swift': '\n'.join(tests)}


# CI 检查生成物与固定源数据一致；显式运行才写入文件。
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for path, content in generate().items():
        if args.check:
            if path.read_text() != content:
                raise SystemExit(f'Stale generated file: {path.relative_to(ROOT)}')
        else:
            path.write_text(content)


if __name__ == '__main__':
    main()
