"""Guard specialist CI against diverging from declared acceptance manifests."""
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))
import acceptance_criteria as acceptance


class AcceptanceWorkflowWiringTest(unittest.TestCase):
    def test_issue_workflows_execute_their_manifest(self):
        cases = (
            ("580", "temp-issue-580.yml", "local_stt_tools_test.dart"),
            ("590", "temp-issue-590.yml", "playwright_transport_wiring_test.dart"),
        )
        for issue, workflow_name, additional_test in cases:
            with self.subTest(issue=issue):
                manifest_path = f"docs/acceptance/temporary/issue-{issue}.json"
                data = acceptance.load_manifest(ROOT, ROOT / manifest_path)
                selected = acceptance.expected_tests(data["issues"], "unit")
                self.assertTrue(selected)
                self.assertTrue(any(additional_test in path for path in selected))
                workflow = (
                    ROOT / ".github" / "workflows" / workflow_name
                ).read_text(encoding="utf-8")
                self.assertIn(manifest_path, workflow)
                self.assertIn("python3 tool/acceptance_criteria.py", workflow)
                self.assertIn("--run-tests", workflow)
                self.assertIn("--out-dir build/acceptance/", workflow)
                self.assertNotIn("run: flutter test test/mcp", workflow)
                self.assertNotIn("run: flutter test test/local_stt_tools_test.dart",
                                 workflow)

    def test_central_pr_lane_runs_issue_linked_manifest_tests(self):
        workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("python3 tool/issue_task_ci.py --mode unit", workflow)
        self.assertIn("test_acceptance_workflow_wiring.py", workflow)
        self.assertIn("run: python3 tool/ci_gate.py", workflow)


if __name__ == "__main__":
    unittest.main()
