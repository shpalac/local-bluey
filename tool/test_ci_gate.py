"""Fail-closed coverage for the stable CI merge gate."""
import unittest
from ci_gate import ALWAYS_REQUIRED, REQUIRED_WHEN_SELECTED, failures


class GateTest(unittest.TestCase):
    def setUp(self):
        self.flags = {lane: False for lane in REQUIRED_WHEN_SELECTED.values()}
        self.jobs = {"detect": {"result": "success"}}
        self.jobs.update({job: {"result": "skipped"} for job in REQUIRED_WHEN_SELECTED})
        self.jobs.update({job: {"result": "success"} for job in ALWAYS_REQUIRED})

    def test_docs_only_skip_is_valid(self):
        self.assertEqual(failures({"lanes": self.flags}, self.jobs), [])

    def test_required_lane_must_pass(self):
        self.flags["test"] = True
        self.assertTrue(failures({"lanes": self.flags}, self.jobs))
        self.jobs["test"] = {"result": "success"}
        self.assertEqual(failures({"lanes": self.flags}, self.jobs), [])

    def test_failure_is_not_ignored_for_unselected_job(self):
        self.jobs["android"] = {"result": "failure"}
        self.assertTrue(failures({"lanes": self.flags}, self.jobs))

    def test_cancelled_or_missing_is_never_green(self):
        for result in ("cancelled", "missing"):
            with self.subTest(result=result):
                self.jobs["security"] = {"result": result}
                self.assertTrue(failures({"lanes": self.flags}, self.jobs))

    def test_incomplete_plan_fails_closed(self):
        self.flags.pop("test")
        self.assertTrue(failures({"lanes": self.flags}, self.jobs))

    def test_detector_failure_blocks_merge(self):
        self.jobs["detect"] = {"result": "failure"}
        self.assertTrue(failures({"lanes": self.flags}, self.jobs))


if __name__ == "__main__":
    unittest.main()
