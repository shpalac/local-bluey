"""Fail-closed tests for the trusted approved-author auto-merge policy."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import approved_author_auto_merge as merge

REPO = "shpalac/local-bluey"


class ApprovedAuthorAutoMergeTests(unittest.TestCase):
    def setUp(self):
        self.event = {
            "action": "opened",
            "repository": {"full_name": REPO},
            "pull_request": {
                "number": 918,
                "draft": False,
                "user": {"login": "shpalac"},
                "base": {"ref": "main"},
                "head": {"repo": {"full_name": REPO}},
            },
        }
        self.approved = {"shpalac"}

    def eligible(self):
        return merge.eligible_pr_number(self.event, REPO, self.approved)

    def test_approved_open_pr_is_queued(self):
        self.assertEqual(self.eligible(), 918)

    def test_ready_for_review_requeues_draft(self):
        self.event["action"] = "ready_for_review"
        self.assertEqual(self.eligible(), 918)
        self.event["pull_request"]["draft"] = True
        self.assertIsNone(self.eligible())

    def test_unapproved_author_cannot_queue(self):
        self.event["pull_request"]["user"]["login"] = "untrusted"
        self.assertIsNone(self.eligible())
        self.approved.clear()
        self.event["pull_request"]["user"]["login"] = "shpalac"
        self.assertIsNone(self.eligible())

    def test_forks_other_branches_and_repositories_are_denied(self):
        original = copy.deepcopy(self.event)
        self.event["pull_request"]["head"]["repo"]["full_name"] = "someone/fork"
        self.assertIsNone(self.eligible())
        self.event = copy.deepcopy(original)
        self.event["pull_request"]["base"]["ref"] = "feature"
        self.assertIsNone(self.eligible())
        self.event = copy.deepcopy(original)
        self.event["repository"]["full_name"] = "other/repo"
        self.assertIsNone(self.eligible())

    def test_unexpected_events_and_invalid_numbers_are_denied(self):
        self.event["action"] = "closed"
        self.assertIsNone(self.eligible())
        self.event["action"] = "synchronize"
        self.event["pull_request"]["number"] = True
        self.assertIsNone(self.eligible())
        self.event["pull_request"]["number"] = 0
        self.assertIsNone(self.eligible())
        self.event["pull_request"]["number"] = 918
        self.assertEqual(self.eligible(), 918)

    def test_missing_metadata_fails_closed(self):
        for key in ("user", "head", "base", "number"):
            original = self.event["pull_request"].pop(key)
            self.assertIsNone(self.eligible())
            self.event["pull_request"][key] = original

    def test_parser_supports_comma_space_and_case_insensitive_logins(self):
        self.assertEqual(
            merge.parse_approved_authors(" Shpalac, Agent-Bot\nother "),
            {"shpalac", "agent-bot", "other"},
        )
        self.event["pull_request"]["user"]["login"] = "SHPALAC"
        self.assertEqual(self.eligible(), 918)

    def test_invalid_allowlist_entry_fails_closed(self):
        for value in ("shpalac;other", "bad/login", "@someone"):
            with self.assertRaises(ValueError):
                merge.parse_approved_authors(value)

    @patch("approved_author_auto_merge.subprocess.run")
    def test_queues_only_squash_auto_merge(self, run):
        merge.queue_auto_merge(REPO, 918)
        run.assert_called_once_with(
            ["gh", "pr", "merge", "918", "--repo", REPO, "--auto", "--squash"],
            check=True,
        )


if __name__ == "__main__":
    unittest.main()
