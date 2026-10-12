"""Verify BLU-001..003 issue acceptance cannot claim false CI completion."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import acceptance_criteria as acceptance
import blu_001_003_acceptance as blu

PROJECT = Path(__file__).resolve().parent.parent


class BluAcceptanceContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for number in blu.ISSUES:
            relative = f"docs/acceptance/issue-{number}.json"
            dest = self.root / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(PROJECT / relative, dest)
            issue = json.loads(dest.read_text())["issues"][0]
            for criterion in issue["criteria"]:
                for test in criterion.get("tests", []):
                    source = PROJECT / test["file"]
                    target = self.root / test["file"]
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if not target.exists():
                        shutil.copyfile(source, target)

    def modify(self, number, change):
        path = self.root / f"docs/acceptance/issue-{number}.json"
        data = json.loads(path.read_text())
        change(data["issues"][0])
        path.write_text(json.dumps(data), encoding="utf-8")

    def test_each_numbered_criterion_is_explicit(self):
        data = blu.load_contracts(self.root)
        self.assertEqual([issue["number"] for issue in data["issues"]], list(blu.ISSUES))
        for issue in data["issues"]:
            names = {c["id"] for c in issue["criteria"]}
            self.assertTrue(blu.REQUIRED_AC <= names)
            self.assertTrue(any(c["type"] == "automated" for c in issue["criteria"]))

    def test_incomplete_hardware_and_review_criteria_cannot_pass(self):
        data = blu.load_contracts(self.root)
        succeeded = {
            (test["file"], test["name"]): True
            for issue in data["issues"]
            for criterion in issue["criteria"]
            for test in criterion.get("tests", [])
        }
        report, _ = acceptance.render(data, succeeded)
        self.assertTrue(report["automatedSuitesPassed"])
        self.assertFalse(report["issueCompletionCertified"])
        self.assertTrue(all(not issue["acceptanceComplete"] for issue in report["issues"]))
        blu_003 = next(issue for issue in report["issues"] if issue["number"] == 556)
        self.assertTrue(any(c["status"] == "not_implemented"
                            for c in blu_003["criteria"]))

    def test_missing_numbered_criterion_fails_closed(self):
        self.modify(555, lambda issue: issue["criteria"].__setitem__(
            slice(None), [c for c in issue["criteria"] if c["id"] != "ac_2"]
        ))
        with self.assertRaisesRegex(acceptance.ManifestError, "ac_2"):
            blu.load_contracts(self.root)

    def test_native_gap_cannot_be_labeled_done(self):
        def alter(issue):
            entry = next(c for c in issue["criteria"] if c["id"] == "ac_3")
            entry["type"] = "manual"
            entry["reason"] = "A reviewer has not signed off yet"
        self.modify(556, alter)
        with self.assertRaisesRegex(acceptance.ManifestError, "expected gap"):
            blu.load_contracts(self.root)

    def test_missing_or_renamed_test_does_not_count(self):
        path = self.root / "test/activity_step_test.dart"
        path.write_text("test('an unrelated test', () {});", encoding="utf-8")
        with self.assertRaisesRegex(acceptance.ManifestError, "declared test name"):
            blu.load_contracts(self.root)

    def test_missing_manifest_does_not_silently_skip_issue(self):
        (self.root / "docs/acceptance/issue-554.json").unlink()
        with self.assertRaises(acceptance.ManifestError):
            blu.load_contracts(self.root)

    def test_failure_does_not_certify_suites(self):
        data = blu.load_contracts(self.root)
        report, _ = acceptance.render(data, {})
        self.assertFalse(report["automatedSuitesPassed"])
        self.assertTrue(all(not issue["acceptanceComplete"] for issue in report["issues"]))


if __name__ == "__main__":
    unittest.main()
