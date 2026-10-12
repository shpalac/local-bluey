"""Issue hygiene must be idempotent and must not echo the issue body."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from issue_task_hygiene import MARKER, record_missing_contract
from issue_task_ci import ContractError


class HygieneTests(unittest.TestCase):
    def test_posts_once_with_bounded_message(self):
        requests = []
        def api(url, token, payload=None):
            requests.append((url, token, payload))
            return [] if payload is None else {"id": 17}
        result = record_missing_contract(
            "shpalac/local-bluey", 42, "fake-token",
            "missing acceptance checklist", request=api
        )
        self.assertTrue(result)
        self.assertEqual(len(requests), 2)
        self.assertIn(MARKER, requests[1][2]["body"])
        self.assertIn("missing acceptance checklist", requests[1][2]["body"])

    def test_does_not_spam_existing_issue(self):
        requests = []
        def api(url, token, payload=None):
            requests.append(payload)
            return [{"body": MARKER + "\nPrior comment"}]
        self.assertFalse(record_missing_contract(
            "shpalac/local-bluey", 42, "fake-token", "bad body", request=api
        ))
        self.assertEqual(requests, [None])

    def test_rejects_untrusted_repository_context(self):
        with self.assertRaises(ContractError):
            record_missing_contract("bad/url/extra", 42, "fake-token", "bad")
        with self.assertRaises(ContractError):
            record_missing_contract("shpalac/local-bluey", 0, "fake-token", "bad")
        with self.assertRaises(ContractError):
            record_missing_contract("shpalac/local-bluey", 42, "", "bad")


if __name__ == "__main__":
    unittest.main()
