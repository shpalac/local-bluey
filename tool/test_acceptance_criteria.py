"""Pure-stdlib fixtures for acceptance evidence reporting and safety boundaries."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import acceptance_criteria as ac


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'test').mkdir()
        (self.root / 'test' / 'sample_test.dart').write_text("test('always rejects unknown', () {});\n", encoding='utf-8')
        self.sample = {
            'version': 1,
            'issues': [{'number': 555, 'title': 'Schema', 'criteria': [
                {'id': 'schema_validation', 'requirement': 'Unknown schema denied',
                 'type': 'automated', 'tests': [{'file': 'test/sample_test.dart', 'name': 'always rejects unknown'}]},
                {'id': 'hardware_review', 'requirement': 'Physical validation',
                 'type': 'manual', 'reason': 'A real device and reviewer are required'},
                {'id': 'storage_wiring', 'requirement': 'Encrypted store integration',
                 'type': 'gap', 'reason': 'Not implemented'},
            ]}]
        }
        self.manifest = self.root / 'matrix.json'
        self.write()

    def write(self):
        self.manifest.write_text(json.dumps(self.sample), encoding='utf-8')

    def load(self):
        return ac.load_manifest(self.root, self.manifest)

    def test_valid_automated_manual_gap(self):
        report, markdown = ac.render(self.load(), {('test/sample_test.dart', 'always rejects unknown'): True})
        self.assertTrue(report['automatedSuitesPassed'])
        self.assertFalse(report['issueCompletionCertified'])
        self.assertFalse(report['issues'][0]['acceptanceComplete'])
        statuses = [c['status'] for c in report['issues'][0]['criteria']]
        self.assertEqual(statuses, ['passed', 'manual_required', 'not_implemented'])
        self.assertIn('do not close automatically', markdown)

    def test_automated_failure_returns_failed_evidence(self):
        report, _ = ac.render(self.load(), {('test/sample_test.dart', 'always rejects unknown'): False})
        self.assertFalse(report['automatedSuitesPassed'])
        self.assertEqual(report['issues'][0]['criteria'][0]['status'], 'failed')

    def test_test_never_claimed_passed_without_execution(self):
        report, _ = ac.render(self.load(), None)
        self.assertEqual(report['issues'][0]['criteria'][0]['status'], 'not_run')
        self.assertFalse(report['automatedSuitesPassed'], 'validate-only must not report passing tests')

    def test_missing_test_name_denies_manifest(self):
        self.sample['issues'][0]['criteria'][0]['tests'][0]['name'] = 'imagined test'
        self.write()
        with self.assertRaises(ac.ManifestError):
            self.load()

    def test_unknown_schema_denies_manifest(self):
        self.sample['version'] = 2
        self.write()
        with self.assertRaises(ac.ManifestError):
            self.load()

    def test_duplicate_criterion_denies_manifest(self):
        self.sample['issues'][0]['criteria'].append(self.sample['issues'][0]['criteria'][0])
        self.write()
        with self.assertRaises(ac.ManifestError):
            self.load()

    def test_missing_review_reason_denies_manifest(self):
        del self.sample['issues'][0]['criteria'][1]['reason']
        self.write()
        with self.assertRaises(ac.ManifestError):
            self.load()

    def test_path_escape_denies_manifest(self):
        self.sample['issues'][0]['criteria'][0]['tests'][0]['file'] = '../secrets_test.dart'
        self.write()
        with self.assertRaises(ac.ManifestError):
            self.load()

    @patch('acceptance_criteria.subprocess.run')
    def test_failure_only_reports_filename_not_stdout(self, run):
        run.return_value = subprocess.CompletedProcess([], 1, stdout=b'password=SECRET')
        with patch('builtins.print') as output:
            results = ac.run_suites({'test/sample_test.dart': {'always rejects unknown'}}, self.root, 5)
        self.assertEqual(results, {('test/sample_test.dart', 'always rejects unknown'): False})
        emitted = ' '.join(str(x) for x in output.call_args_list)
        self.assertNotIn('SECRET', emitted)
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ['flutter', 'test', 'test/sample_test.dart'])
        self.assertEqual(run.call_args.kwargs['timeout'], 5)

    @patch('acceptance_criteria.subprocess.run')
    def test_named_case_must_actually_run_pass_and_not_skip(self, run):
        def events(result='success', skipped=False):
            return (
                json.dumps({'type': 'testStart', 'test': {'id': 7, 'name': 'always rejects unknown'}})
                + '\n' + json.dumps({'type': 'testDone', 'testID': 7, 'result': result, 'skipped': skipped})
                + '\n'
            ).encode()
        spec = {'test/sample_test.dart': {'always rejects unknown'}}
        run.return_value = subprocess.CompletedProcess([], 0, stdout=events())
        with patch('builtins.print'):
            self.assertTrue(ac.run_suites(spec, self.root, 5)[('test/sample_test.dart', 'always rejects unknown')])
            for output in [events(skipped=True), events(result='failure'), b'', events().replace(b'always rejects unknown', b'other test')]:
                run.return_value = subprocess.CompletedProcess([], 0, stdout=output)
                self.assertFalse(ac.run_suites(spec, self.root, 5)[('test/sample_test.dart', 'always rejects unknown')])

    def test_cli_writes_report_in_validate_mode(self):
        rc = ac.main(['--root', str(self.root), '--manifest', 'matrix.json', '--out-dir', 'reports'])
        self.assertEqual(rc, 0)
        report = json.loads((self.root / 'reports' / 'acceptance.json').read_text())
        self.assertEqual(report['issues'][0]['criteria'][0]['status'], 'not_run')
        self.assertTrue((self.root / 'reports' / 'acceptance.md').exists())


if __name__ == '__main__':
    unittest.main()
