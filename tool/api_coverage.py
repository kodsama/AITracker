#!/usr/bin/env python3
"""Reports which exported names no test ever mentions.

Line coverage says a line ran. This says a name was used: a public class,
function, getter or field that only its own library refers to is either dead or
untested, and both are worth seeing.

  python3 tool/api_coverage.py [min-percent]
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKAGES = ['packages/engine', 'packages/mcp', 'packages/cli', 'app']

DECLARATION = re.compile(
    r'^\s*(?:abstract\s+|final\s+|base\s+|interface\s+|sealed\s+|mixin\s+)*'
    r'(?:class|enum|extension|typedef)\s+([A-Z]\w*)',
)
MEMBER = re.compile(
    r'^\s{2,}(?:static\s+|final\s+|const\s+|late\s+)*'
    r'(?:[\w<>?,\s\[\]]+\s+)?(?:get\s+)?([a-z]\w*)\s*(?:\(|=>|;|=)',
)
TOP_LEVEL = re.compile(
    r'^(?:[\w<>?,\s\[\]]+\s+)([a-z]\w*)\s*(?:\(|=>|=)',
)
KEYWORDS = {
    'if', 'for', 'while', 'return', 'switch', 'case', 'assert', 'throw', 'await',
    'yield', 'else', 'try', 'catch', 'finally', 'super', 'this', 'import',
    'export', 'part', 'library', 'typedef', 'const', 'final', 'var', 'void',
    'get', 'set', 'new', 'do', 'in', 'is', 'as', 'with', 'on', 'when',
}


def public_names(package: pathlib.Path) -> dict[str, str]:
    """Public names declared in the package's lib, to the file that holds them.

    Only what a caller could reach: a type or function at the top level, and a
    member directly inside a type. Anything deeper is a local, and nobody's API.
    """
    names: dict[str, str] = {}
    for file in sorted((package / 'lib').rglob('*.dart')):
        depth = 0
        inside_type = False
        for line in file.read_text().splitlines():
            stripped = line.strip()
            if not stripped.startswith('//'):
                if depth == 0:
                    found = DECLARATION.match(line) or TOP_LEVEL.match(line)
                    if found:
                        name = found.group(1)
                        if not name.startswith('_') and name not in KEYWORDS:
                            names.setdefault(name, str(file.relative_to(ROOT)))
                        if DECLARATION.match(line):
                            inside_type = True
                elif depth == 1 and inside_type:
                    found = MEMBER.match(line)
                    if found:
                        name = found.group(1)
                        if not name.startswith('_') and name not in KEYWORDS:
                            names.setdefault(name, str(file.relative_to(ROOT)))
            depth += line.count('{') - line.count('}')
            depth = max(depth, 0)
            if depth == 0:
                inside_type = False
    return names


def test_text() -> str:
    """Everything every test says, in one string."""
    parts = []
    for package in PACKAGES:
        for file in (ROOT / package / 'test').rglob('*.dart'):
            parts.append(file.read_text())
    return '\n'.join(parts)


def main() -> int:
    minimum = float(sys.argv[1]) if len(sys.argv) > 1 else 99.0
    tests = test_text()
    status = 0
    for package in PACKAGES:
        names = public_names(ROOT / package)
        if not names:
            continue
        unused = sorted(
            name
            for name in names
            if not re.search(rf'\b{re.escape(name)}\b', tests)
        )
        used = len(names) - len(unused)
        percent = used / len(names) * 100
        mark = '✓' if percent >= minimum else '✗'
        print(f'{package:<17} {mark} {percent:5.1f}% of {len(names)} names '
              f'({len(unused)} never mentioned by a test)')
        for name in unused:
            print(f'      {name}  ({names[name]})')
        if percent < minimum:
            status = 1
    return status


if __name__ == '__main__':
    sys.exit(main())
