import subprocess
import unittest
from unittest.mock import patch

from check_format import changed_dart_files, formatter_command


class ChangedDartFilesTest(unittest.TestCase):
    def test_initial_push_checks_all_tracked_dart_files(self):
        with patch('check_format.subprocess.run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, b'lib/a.dart\0')
            self.assertEqual(changed_dart_files('0' * 40), ['lib/a.dart'])
            self.assertEqual(run.call_args.args[0], [
                'git', 'ls-files', '-z', '--', '*.dart',
            ])

    def test_diff_includes_existing_renamed_and_copied_files_only(self):
        base = 'a' * 40
        with patch('check_format.subprocess.run') as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 0),
                subprocess.CompletedProcess([], 0, b'lib/copy with spaces.dart\0-new.dart\0'),
            ]
            files = changed_dart_files(base)
            self.assertEqual(files, ['lib/copy with spaces.dart', '-new.dart'])
            self.assertEqual(run.call_args.args[0], [
                'git', 'diff', '--name-only', '--diff-filter=ACMR', '-z',
                base, 'HEAD', '--', '*.dart',
            ])
            self.assertEqual(formatter_command(files), [
                'dart', 'format', '--output=none', '--set-exit-if-changed',
                '--', 'lib/copy with spaces.dart', '-new.dart',
            ])

    def test_unavailable_force_push_base_fails_without_broadening_scope(self):
        with patch('check_format.subprocess.run') as run:
            run.return_value = subprocess.CompletedProcess([], 1, b'')
            with self.assertRaisesRegex(ValueError, 'Base commit is unavailable'):
                changed_dart_files('b' * 40)
            run.assert_called_once()

    def test_rejects_unexpected_base_reference(self):
        with patch('check_format.subprocess.run') as run:
            with self.assertRaises(ValueError):
                changed_dart_files('--output=/tmp/unexpected')
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
