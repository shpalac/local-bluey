"""Fail-closed PR auto-merge selection fixtures."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import issue_auto_merge as merge
from issue_task_ci import ContractError

REPO = "shpalac/local-bluey"
SHA = "a" * 40


class FakeGitHub:
    def __init__(self):
        self.pr = {
            "state": "open", "draft": False,
            "base": {"ref": "main"},
            "head": {"sha": SHA, "repo": {"full_name": REPO}},
            "body": "AutoClose #42", "node_id": "PR_NODE_ID",
            "user": {"login": "shpalac"},
            "auto_merge": None,
        }

    def request(self, path):
        assert path == f"/repos/{REPO}/pulls/85"
        return self.pr


class AutoMergeTests(unittest.TestCase):
    def setUp(self):
        self.client = FakeGitHub()
        self.event = {
            "repository": {"full_name": REPO},
            "action": "completed",
            "workflow_run": {
                "event": "pull_request", "status": "completed",
                "conclusion": "success", "head_sha": SHA,
                "head_repository": {"full_name": REPO},
                "pull_requests": [{"number": 85}],
            },
        }

    def eligible(self):
        return merge.eligible_prs(self.event, REPO, self.client, {"shpalac"})

    def test_green_checked_autoclose_pr_is_eligible(self):
        self.assertEqual(self.eligible(), [(85, "PR_NODE_ID")])

    def test_all_approved_prs_are_eligible_regardless_of_issue_marker(self):
        for body in ["Refs #42", "AutoClose #42", ""]:
            self.client.pr["body"] = body
            self.assertEqual(self.eligible(), [(85, "PR_NODE_ID")])

    def test_requested_ci_queues_while_checks_are_pending(self):
        self.event["action"] = "requested"
        self.event["workflow_run"]["status"] = "queued"
        self.event["workflow_run"]["conclusion"] = None
        self.assertEqual(self.eligible(), [(85, "PR_NODE_ID")])

    def test_requested_with_failed_completed_ci_does_not_queue(self):
        self.event["workflow_run"]["conclusion"] = "failure"
        self.assertEqual(self.eligible(), [])
        self.event["action"] = "requested"
        self.assertEqual(self.eligible(), [])

    def test_red_or_untrusted_ci_never_enables_merge(self):
        for field, value in [("event", "push"), ("conclusion", "failure"),
                             ("status", "in_progress"),
                             ("head_repository", {"full_name": "other/repo"})]:
            original = self.event["workflow_run"][field]
            self.event["workflow_run"][field] = value
            self.assertEqual(self.eligible(), [])
            self.event["workflow_run"][field] = original

    def test_stale_draft_or_already_enabled_pr_is_not_eligible(self):
        for key, value in [("state", "closed"), ("draft", True),
                           ("auto_merge", {"enabled_at": "now"}),
                           ("head", {"sha": "b" * 40}),
                           ("head", {"sha": SHA, "repo": {"full_name": "other/repo"}}),
                           ("base", {"ref": "develop"})]:
            original = self.client.pr[key]
            self.client.pr[key] = value
            self.assertEqual(self.eligible(), [])
            self.client.pr[key] = original

    def test_unapproved_autoclose_pr_is_not_eligible(self):
        self.client.pr["user"]["login"] = "unapproved"
        self.assertEqual(self.eligible(), [])

    def test_invalid_checked_sha_fails(self):
        self.event["workflow_run"]["head_sha"] = "bad"
        with self.assertRaisesRegex(ContractError, "SHA"):
            self.eligible()


if __name__ == "__main__":
    unittest.main()
