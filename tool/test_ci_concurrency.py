"""Regression for SHA-scoped main-branch CI and verified issue closure.

A newer main push must never cancel or replace an earlier merged commit's
verification: issue closure is tied to the exact merge SHA, not the latest
successful run on main.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


class CiConcurrencyContractTest(unittest.TestCase):
    def test_pr_concurrency_cancels_stale_heads_only(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn(
            "group: ci-${{ github.event_name == 'pull_request' && github.ref || github.sha }}",
            workflow,
        )
        self.assertIn(
            "cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
            workflow,
        )
        self.assertNotIn("group: ci-${{ github.ref }}", workflow)
        self.assertNotIn("cancel-in-progress: true", workflow)

    def test_close_workflow_only_accepts_successful_merged_main_ci(self):
        workflow = (ROOT / ".github/workflows/issue-automation.yml").read_text()
        self.assertIn("workflow_run:", workflow)
        self.assertIn("github.event.workflow_run.event == 'push'", workflow)
        self.assertIn("github.event.workflow_run.conclusion == 'success'", workflow)
        self.assertIn("github.event.workflow_run.head_branch == 'main'", workflow)


if __name__ == "__main__":
    unittest.main()
