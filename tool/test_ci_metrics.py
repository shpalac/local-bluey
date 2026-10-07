"""Offline fixtures for the metrics workflow."""
import json
import subprocess
import unittest
from unittest.mock import patch
import ci_metrics


class MetricsTest(unittest.TestCase):
    def response(self, value):
        return subprocess.CompletedProcess([], 0, stdout=json.dumps(value))

    def job(self, seconds, name='test'):
        return dict(name=name, status='completed', started_at='2026-10-01T00:00:00Z',
                    completed_at=f'2026-10-01T00:00:{seconds:02d}Z')

    @patch('ci_metrics.subprocess.run')
    def test_durations_medians_and_single_jq_option(self, run):
        run.side_effect = [self.response([dict(id=1, conclusion='success')]),
                           self.response([self.job(10), self.job(20),
                                          self.job(30, 'android-integration (29)')])]
        text, total, rate, incomplete = ci_metrics.report('owner/repo', 'date')
        self.assertIn('| test | 15s (2 jobs) |', text)
        self.assertIn('| android-integration | 30s (1 jobs) |', text)
        self.assertEqual((total, rate, incomplete), (1, 0, False))
        for call in run.call_args_list:
            command = call.args[0]
            self.assertEqual(command.count('--jq'), 1)
            self.assertNotIn('-q', command)
            self.assertTrue(command[command.index('--jq') + 1].startswith('['))
            self.assertTrue(call.kwargs['check'])

    @patch('ci_metrics.subprocess.run')
    def test_failed_job_read_is_visible_and_fails_report(self, run):
        run.side_effect = [self.response([dict(id=8, conclusion='failure')]),
                           subprocess.CalledProcessError(1, ['gh'])]
        text, total, rate, incomplete = ci_metrics.report('owner/repo', 'date')
        self.assertIn('Incomplete report', text)
        self.assertIn('Run 8: job-duration read failed', text)
        self.assertEqual((total, rate, incomplete), (1, 100, True))

    @patch('ci_metrics.subprocess.run')
    def test_valid_no_matching_jobs_is_not_error(self, run):
        run.side_effect = [self.response([dict(id=1, conclusion='success')]),
                           self.response([])]
        text, _, _, incomplete = ci_metrics.report('owner/repo', 'date')
        self.assertIn('No matching completed jobs', text)
        self.assertFalse(incomplete)

    @patch('ci_metrics.subprocess.run')
    def test_no_runs_is_valid(self, run):
        run.return_value = self.response([])
        text, total, rate, incomplete = ci_metrics.report('owner/repo', 'date')
        self.assertEqual((total, rate, incomplete), (0, 0, False))
        self.assertIn('No matching completed jobs', text)


if __name__ == '__main__':
    unittest.main()
