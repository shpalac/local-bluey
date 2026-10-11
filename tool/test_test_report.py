import json
import unittest

from test_report import parse_report, render_markdown, render_junit


def events(*items):
    return '\n'.join(json.dumps(item) for item in items)


class TestReportTests(unittest.TestCase):
    def stream(self, result='success', skipped=False, terminal=True):
        rows = [
            {'type': 'start', 'protocolVersion': '0.1.1', 'time': 0},
            {'type': 'suite', 'suite': {'id': 1, 'path': '/repo/test/a_test.dart'}, 'time': 0},
            {'type': 'testStart', 'test': {'id': 2, 'suiteID': 1, 'name': 'a < b & שלום'}, 'time': 1000},
            {'type': 'testDone', 'testID': 2, 'result': result, 'skipped': skipped, 'hidden': False, 'time': 1200},
        ]
        if terminal:
            rows.append({'type': 'done', 'success': result == 'success', 'time': 1500})
        return rows

    def test_duration_is_end_minus_start_and_xml_is_escaped(self):
        report = parse_report(events(*self.stream()))
        self.assertEqual(report['tests'][2]['duration'], 200)
        self.assertTrue(report['success'])
        self.assertIn('a &lt; b &amp; שלום', render_junit(report))
        self.assertIn('0.200', render_junit(report))

    def test_failure_skip_and_late_error_remain_distinct(self):
        failed = parse_report(events(*self.stream(result='failure')))
        self.assertFalse(failed['success'])
        self.assertIn('<failure', render_junit(failed))
        skipped = parse_report(events(*self.stream(skipped=True)))
        self.assertIn('<skipped', render_junit(skipped))
        rows = self.stream()
        rows.insert(-1, {'type': 'error', 'testID': 2, 'error': 'late', 'isFailure': False, 'time': 1300})
        self.assertFalse(parse_report(events(*rows))['success'])

    def test_missing_terminal_and_unfinished_test_fail(self):
        report = parse_report(events(*self.stream(terminal=False)))
        self.assertFalse(report['success'])
        self.assertIn('INCOMPLETE', render_markdown(report))
        rows = self.stream()
        del rows[3]
        self.assertFalse(parse_report(events(*rows))['success'])

    def test_malformed_truncated_wrong_protocol_and_null_terminal_fail(self):
        for stream in (events(*self.stream()) + '\n{',
                       events(*self.stream()) + '\n[]',
                       events({'type': 'start', 'protocolVersion': '9.0', 'time': 0}),
                       events(*self.stream()[:-1], {'type': 'done', 'success': None, 'time': 1500})):
            self.assertFalse(parse_report(stream)['success'])

    def test_failed_run_without_failed_test_is_red_in_junit(self):
        rows = self.stream()
        rows[-1]['success'] = False
        report = parse_report(events(*rows))
        self.assertFalse(report['success'])
        self.assertIn('<failure', render_junit(report))

    def test_hidden_loader_error_cannot_make_run_green(self):
        rows = self.stream()
        rows[3].update(hidden=True, result='error')
        self.assertFalse(parse_report(events(*rows))['success'])

    def test_interleaved_tests_get_individual_durations(self):
        rows = self.stream()
        rows.insert(3, {'type': 'testStart', 'test': {'id': 3, 'suiteID': 1, 'name': 'other'}, 'time': 1100})
        rows.insert(-1, {'type': 'testDone', 'testID': 3, 'result': 'success', 'time': 1400})
        report = parse_report(events(*rows))
        self.assertEqual(report['tests'][3]['duration'], 300)
        self.assertEqual(report['tests'][2]['duration'], 200)


if __name__ == '__main__':
    unittest.main()
