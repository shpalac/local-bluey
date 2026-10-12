"""Regression tests for issue-scoped acceptance and promotion rules."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import issue_task_ci as task


class IssueTaskTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ("test/issues", "integration_test/features",
                       "docs/acceptance/temporary", "docs/acceptance/permanent"):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        (self.root / "test/issues/issue_42_test.dart").write_text(
            "test('rejects invalid request', () {});\n", encoding="utf-8"
        )
        (self.root / "integration_test/features/feature_test.dart").write_text(
            "testWidgets('feature works end to end', (tester) async {});\n",
            encoding="utf-8",
        )
        self.body = (
            "## Acceptance criteria\n"
            "- [ ] AC-1: Reject invalid request without side effects.\n"
            "\n## CI and validation\n"
            "Run named acceptance suites.\n"
        )
        self.write_manifest("temporary", [
            {
                "id": "ac_1",
                "requirement": "Reject malformed input",
                "type": "automated",
                "tests": [{
                    "file": "test/issues/issue_42_test.dart",
                    "name": "rejects invalid request",
                }],
            },
        ])

    def write_manifest(self, folder, criteria, number=42):
        path = self.root / f"docs/acceptance/{folder}/issue-{number}.json"
        path.write_text(json.dumps({
            "version": 1,
            "issues": [{"number": number, "title": "Feature", "criteria": criteria}],
        }), encoding="utf-8")
        return path

    def promotion(self):
        (self.root / "docs/acceptance/temporary/issue-42.json").unlink()
        return self.write_manifest("permanent", [
            {
                "id": "ac_1",
                "requirement": "Complete the full user journey",
                "type": "automated",
                "tests": [{
                    "file": "integration_test/features/feature_test.dart",
                    "name": "feature works end to end",
                }],
            },
        ])

    def check(self, reference, mode="unit", runner=None, body=None):
        return task.check(
            self.root, "shpalac/local-bluey", reference, "",
            mode, issue_fetcher=lambda repo, number, token: self.body if body is None else body,
            runner=runner or (lambda tests, root, timeout: {
                (path, name): True for path, names in tests.items() for name in names
            }),
        )

    def test_negated_close_keywords_do_not_link_or_close(self):
        self.assertEqual(
            task.linked_issues("Refs #554. Do not close #557. Never fix #558."),
            {554: False},
        )

    def test_references_do_not_implicitly_close(self):
        self.assertEqual(
            task.linked_issues("Refs #42\nCloses #42\nRefs #43\nFixes #44"),
            {42: True, 43: False, 44: True},
        )

    def test_markdown_examples_are_not_live_issue_links(self):
        tick = chr(96)
        sample = (f"Example: {tick}Closes #123{tick}\n"
                  f"{tick * 3}text\nRefs #234\n{tick * 3}\n"
                  "Refs #42")
        self.assertEqual(task.linked_issues(sample), {42: False})

    def test_requires_checklisted_acceptance_criteria(self):
        with self.assertRaises(task.ContractError):
            task.validate_issue_body("## Acceptance criteria\nUnknown\n## CI plan\n", 42)

    def test_numbered_criteria_must_map_to_evidence(self):
        self.assertTrue(self.check("Refs #42"))
        self.body = self.body.replace("AC-1:", "AC-2:")
        with self.assertRaisesRegex(task.ContractError, "missing test mappings"):
            self.check("Refs #42")

    def test_unnumbered_backlog_cannot_auto_close(self):
        self.promotion()
        self.body = self.body.replace("AC-1:", "Expected:")
        with self.assertRaisesRegex(task.ContractError, "number all acceptance"):
            self.check("Closes #42")

    def test_partially_numbered_acceptance_is_rejected(self):
        self.body = self.body.replace("\n## CI and validation", "\n- [ ] Another criterion without a number.\n\n## CI and validation")
        with self.assertRaisesRegex(task.ContractError, "number every criterion"):
            self.check("Refs #42")

    def test_requires_ci_plan(self):
        with self.assertRaises(task.ContractError):
            task.validate_issue_body("## Acceptance criteria\n- [ ] Real test case has outcomes\n", 42)

    def test_temporary_manifest_runs_named_issue_tests(self):
        invocations = []
        def run(tests, root, timeout):
            invocations.append(tests)
            return {(path, name): True for path, names in tests.items() for name in names}
        self.assertTrue(self.check("Refs #42", runner=run))
        self.assertEqual(invocations, [{
            "test/issues/issue_42_test.dart": {"rejects invalid request"},
        }])

    def test_temporary_manifest_cannot_close(self):
        with self.assertRaisesRegex(task.ContractError, "permanent"):
            self.check("Closes #42")

    def test_permanent_requires_real_named_integration_test(self):
        temporary = self.root / "docs/acceptance/temporary/issue-42.json"
        temporary.unlink()
        bad = self.write_manifest("permanent", [{
            "id": "only_unit",
            "requirement": "Only a unit test",
            "type": "automated",
            "tests": [{
                "file": "test/issues/issue_42_test.dart",
                "name": "rejects invalid request",
            }],
        }])
        with self.assertRaisesRegex(task.ContractError, "integration_test/"):
            self.check("Closes #42")
        bad.unlink()
        self.write_manifest("temporary", [{
            "id": "ac_1", "requirement": "Reject malformed input",
            "type": "automated", "tests": [{
                "file": "test/issues/issue_42_test.dart",
                "name": "rejects invalid request",
            }],
        }])
        self.promotion()
        self.assertTrue(self.check("Closes #42", mode="integration"))

    def test_temporary_not_allowed_after_promotion(self):
        self.write_manifest("permanent", [{
            "id": "end_to_end",
            "requirement": "Integrated behavior",
            "type": "automated",
            "tests": [{
                "file": "integration_test/features/feature_test.dart",
                "name": "feature works end to end",
            }],
        }])
        with self.assertRaisesRegex(task.ContractError, "remove temporary"):
            self.check("Closes #42")

    def test_incomplete_gap_cannot_close(self):
        path = self.promotion()
        manifest = json.loads(path.read_text())
        manifest["issues"][0]["criteria"].append({
            "id": "missing_wiring",
            "requirement": "Wire real executor",
            "type": "gap",
            "reason": "Not implemented",
        })
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(task.ContractError, "outstanding"):
            self.check("Closes #42")
        self.assertTrue(self.check("Refs #42", mode="integration"))

    def test_manual_evidence_never_auto_certified(self):
        path = self.promotion()
        manifest = json.loads(path.read_text())
        manifest["issues"][0]["criteria"].append({
            "id": "hardware_permission",
            "requirement": "Real OS permission behavior",
            "type": "manual",
            "reason": "Requires physical host and reviewer",
        })
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(task.ContractError, "manual"):
            self.check("Closes #42")

    def test_failed_or_skipped_test_blocks(self):
        self.assertFalse(self.check(
            "Refs #42", runner=lambda tests, root, timeout: {
                ("test/issues/issue_42_test.dart", "rejects invalid request"): False,
            },
        ))

    def test_missing_manifest_blocks_linked_pr(self):
        (self.root / "docs/acceptance/temporary/issue-42.json").unlink()
        with self.assertRaisesRegex(task.ContractError, "missing issue-specific"):
            self.check("Refs #42")

    def test_missing_named_test_blocks(self):
        path = self.root / "test/issues/issue_42_test.dart"
        path.write_text("test('a different test', () {});\n")
        with self.assertRaisesRegex(task.ContractError, "declared test name"):
            self.check("Refs #42")

    def test_unrelated_pr_passes_without_manifest(self):
        self.assertTrue(self.check("Docs: adjust whitespace only"))


if __name__ == "__main__":
    unittest.main()
