import unittest
from unittest.mock import patch
import subprocess
import tempfile
from pathlib import Path

from ci_control import classify, select, verify_gate


class ChangeSelectionTests(unittest.TestCase):
    def test_documentation_does_not_build_apps(self):
        selected = classify(['README.md', 'docs/screenshots/hero.png'])
        self.assertTrue(selected['doc_contracts'])
        self.assertFalse(any(value for lane, value in selected.items() if lane != 'doc_contracts'))

    def test_dart_changes_build_all_clients_but_not_codeql(self):
        selected = classify(['lib/main.dart'])
        for lane in ('dart', 'macos', 'ios', 'android', 'linux', 'integration'):
            self.assertTrue(selected[lane])
        self.assertFalse(selected['swift'])
        self.assertFalse(selected['kotlin'])

    def test_tests_do_not_rebuild_native_clients(self):
        selected = classify(['test/example_test.dart'])
        self.assertTrue(selected['dart'])
        self.assertFalse(selected['macos'])

    def test_native_changes_select_the_platform(self):
        selected = classify(['android/app/src/main/kotlin/MainActivity.kt'])
        self.assertTrue(selected['android'])
        self.assertTrue(selected['integration'])
        self.assertTrue(selected['kotlin'])
        self.assertFalse(selected['swift'])

    def test_dependencies_ci_and_unknown_paths_fail_closed(self):
        for path in ('pubspec.lock', '.flutter-version', '.github/workflows/ci.yml',
                     'tool/ci_control.py', 'new-build-config', 'Shared/Wire.swift'):
            with self.subTest(path=path):
                self.assertTrue(all(classify([path]).values()))

    def test_empty_diff_selects_nothing(self):
        self.assertFalse(any(classify([]).values()))

    def test_pr_diff_includes_deleted_and_renamed_inputs(self):
        event = {'pull_request': {'base': {'sha': 'base'}, 'head': {'sha': 'head'}}}
        with patch('subprocess.check_output', return_value=b'ios/Removed.swift\0README.md\0') as git:
            selected = select(event, 'pull_request')
        self.assertTrue(selected['ios'])
        self.assertEqual(git.call_args.args[0][-1], 'base...head')

    def test_push_diff_and_missing_ancestor(self):
        with patch('subprocess.check_output', return_value=b'docs/notes.md\0') as git:
            self.assertFalse(any(select({'before': 'a', 'after': 'b'}, 'push').values()))
        self.assertEqual(git.call_args.args[0][-1], 'a..b')
        with patch('subprocess.check_output', side_effect=subprocess.CalledProcessError(128, 'git')):
            self.assertTrue(all(select({'before': 'a', 'after': 'b'}, 'push').values()))

    def test_schedule_and_manual_selection_are_explicit(self):
        self.assertFalse(any(select({}, 'schedule').values()))
        self.assertTrue(all(select({}, 'workflow_dispatch').values()))
        self.assertTrue(all(select({'before': '0' * 40, 'after': 'b'}, 'push').values()))

    def test_real_git_rename_out_of_lib_still_validates_deleted_source(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args]).decode().strip()
            git('init', '-q')
            git('config', 'user.name', 'CI fixture')
            git('config', 'user.email', 'ci@example.test')
            root = Path(directory)
            (root / 'lib').mkdir()
            (root / 'lib/example.dart').write_text('void main() {}\n')
            git('add', '.')
            git('commit', '-qm', 'base')
            base = git('rev-parse', 'HEAD')
            (root / 'docs').mkdir()
            git('mv', 'lib/example.dart', 'docs/example.dart')
            git('commit', '-qm', 'move')
            head = git('rev-parse', 'HEAD')
            original = subprocess.check_output
            def in_fixture(args, **kwargs):
                return original(args, cwd=directory, **kwargs)
            with patch('subprocess.check_output', side_effect=in_fixture):
                selected = select({'before': base, 'after': head}, 'push')
            self.assertTrue(selected['dart'])
            self.assertTrue(selected['ios'])


class RequiredGateTests(unittest.TestCase):
    def test_expected_success_and_intentional_skip_pass(self):
        verify_gate({'test': True, 'ios': False}, {
            'test': {'result': 'success'}, 'ios': {'result': 'skipped'}})

    def test_required_failures_cancellations_and_skips_fail(self):
        for result in ('failure', 'cancelled', 'skipped', None):
            with self.subTest(result=result), self.assertRaises(ValueError):
                verify_gate({'test': True}, {'test': {'result': result}})

    def test_missing_jobs_and_unexpected_failures_fail(self):
        with self.assertRaises(ValueError):
            verify_gate({'test': True}, {})
        with self.assertRaises(ValueError):
            verify_gate({'test': False}, {'test': {'result': 'failure'}})

    def test_unselected_success_is_safe(self):
        verify_gate({'test': False}, {'test': {'result': 'success'}})


if __name__ == '__main__':
    unittest.main()
