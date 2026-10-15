"""Regression guard: all expensive jobs depend on cheap static preflight."""
from pathlib import Path
import re
import unittest


CI = (Path(__file__).resolve().parent.parent /
      ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")


def job_body(name):
    match = re.search(r"(?ms)^  " + re.escape(name) +
                      r":\n(.*?)(?=^  [a-z][a-z0-9_-]+:\n|\Z)", CI)
    if match is None:
        raise AssertionError(f"missing job: {name}")
    return match.group(1)


class PreflightWiringTest(unittest.TestCase):
    def test_expensive_lanes_wait_for_preflight_but_not_full_tests(self):
        for lane in ("build-macos", "build-ios", "android",
                     "android-integration", "linux"):
            with self.subTest(lane=lane):
                body = job_body(lane)
                self.assertIn("needs: [detect, static]", body)
                self.assertIn("needs.static.result == 'success'", body)
                self.assertNotIn("needs: [detect, static, test]", body)

    def test_merge_gate_still_requires_every_selected_lane(self):
        build = job_body("build")
        for lane in ("static", "test", "build-macos", "build-ios", "android",
                     "android-integration", "linux", "acceptance-evidence",
                     "security", "pinned-actions"):
            self.assertIn(lane, build)
        self.assertIn("run: python3 tool/ci_gate.py", build)

    def test_single_concurrent_impacted_test_command(self):
        selected = job_body("test")
        self.assertIn("python3 tool/ci_impacted_tests.py", selected)
        self.assertIn('--concurrency=6 --reporter expanded', selected)
        self.assertNotIn("for shard in 0 1", selected)
        self.assertIn("flutter test --coverage --reporter expanded", selected)
        self.assertIn("dart run tool/check_coverage.dart", selected)


if __name__ == "__main__":
    unittest.main()
