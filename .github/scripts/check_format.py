"""Check Dart formatting for paths changed since a Git commit."""

import argparse
import os
import re
import subprocess


def changed_dart_files(base):
    if not re.fullmatch(r'[0-9a-f]{40}', base):
        raise ValueError('Expected a full Git commit SHA.')

    if base == '0' * 40:
        print('Initial push. Checking all tracked Dart files.')
        command = ['git', 'ls-files', '-z', '--', '*.dart']
    else:
        base_commit = subprocess.run(
            ['git', 'cat-file', '-e', f'{base}^{{commit}}'],
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if base_commit.returncode != 0:
            raise ValueError('Base commit is unavailable. Cannot identify changed Dart files.')

        command = [
            'git', 'diff', '--name-only', '--diff-filter=ACMR', '-z',
            base, 'HEAD', '--', '*.dart',
        ]

    output = subprocess.run(command, stdout=subprocess.PIPE, check=True).stdout
    return [os.fsdecode(path) for path in output.split(b'\0') if path]


def formatter_command(paths):
    return ['dart', 'format', '--output=none', '--set-exit-if-changed', '--', *paths]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', help='Full base SHA, or 40 zeros for an initial push')
    base = parser.parse_args().base

    try:
        paths = changed_dart_files(base)
    except ValueError as error:
        parser.error(str(error))

    if not paths:
        print('No changed Dart files to format.')
        return 0

    return subprocess.run(formatter_command(paths), check=False).returncode


if __name__ == '__main__':
    raise SystemExit(main())
