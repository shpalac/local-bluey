"""Offline regression fixtures for post-main-CI issue closure."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import issue_auto_close as closer
from issue_task_ci import ContractError

REPO = "shpalac/local-bluey"
HEAD = "a" * 40
MERGE = "b" * 40
BASE = f"/repos/{REPO}"


class FakeGitHub:
    def __init__(self):
        self.writes = []
        self.routes = {
            f"{BASE}/commits/{MERGE}/pulls": [{"number": 85}],
            f"{BASE}/pulls/85": {
                "number": 85, "merged_at": "2026-10-14T20:00:00Z",
                "merge_commit_sha": MERGE, "base": {"ref": "main"},
                "head": {"sha": HEAD}, "body": "AutoClose #42",
            },
            f"{BASE}/actions/workflows/ci.yml/runs"
            f"?event=pull_request&head_sha={HEAD}&per_page=100": {
                "workflow_runs": [{
                    "event": "pull_request", "head_sha": HEAD,
                    "status": "completed", "conclusion": "success",
                    "pull_requests": [{"number": 85}],
                }],
            },
            f"{BASE}/issues/42": {
                "number": 42, "state": "open",
                "body": (
                    "## Acceptance criteria\n"
                    "- [ ] AC-1: Reject malformed inputs with no side effects.\n"
                    "## CI and validation\nRun issue-specific tests.\n"
                ),
            },
            f"{BASE}/issues/42/comments?per_page=100": [],
        }

    def request(self, path, method="GET", payload=None):
        if method == "GET":
            if path not in self.routes:
                raise AssertionError(f"unmocked route: {path}")
            return copy.deepcopy(self.routes[path])
        self.writes.append((method, path, payload))
        if method == "PATCH" and path == f"{BASE}/issues/42":
            self.routes[path]["state"] = payload["state"]
        if method == "POST" and path == f"{BASE}/issues/42/comments":
            self.routes[f"{path}?per_page=100"].append({"body": payload["body"]})
        return {}


class IssueAutoCloseTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        path = self.root / "test/issues/issue_42_test.dart"
        path.parent.mkdir(parents=True)
        path.write_text("test('rejects invalid', () {});\n", encoding="utf-8")
        self.manifest = self.root / "docs/acceptance/temporary/issue-42.json"
        self.manifest.parent.mkdir(parents=True)
        self.write_manifest([{
            "id": "ac_1", "requirement": "Reject malformed inputs",
            "type": "automated", "tests": [{
                "file": "test/issues/issue_42_test.dart", "name": "rejects invalid",
            }],
        }])
        self.api = FakeGitHub()
        self.event = {
            "repository": {"full_name": REPO},
            "workflow_run": {
                "event": "push", "status": "completed",
                "conclusion": "success", "head_branch": "main",
                "head_repository": {"full_name": REPO}, "head_sha": MERGE,
            },
        }

    def write_manifest(self, criteria):
        self.manifest.write_text(json.dumps({
            "version": 1,
            "issues": [{"number": 42, "title": "Reject malformed inputs",
                        "criteria": criteria}],
        }), encoding="utf-8")

    def process(self):
        return closer.process(self.event, REPO, self.root, self.api)

    def test_successful_merged_pr_closes_with_evidence(self):
        self.assertEqual(self.process(), [42])
        self.assertEqual([action[0] for action in self.api.writes], ["POST", "PATCH"])
        self.assertEqual(self.api.writes[-1][2]["state"], "closed")
        self.assertIn(MERGE, self.api.writes[0][2]["body"])

    def test_repeated_workflow_does_not_reclose(self):
        self.assertEqual(self.process(), [42])
        self.assertEqual(self.process(), [])
        self.assertEqual(len(self.api.writes), 2)

    def test_verified_refs_close_after_successful_main_ci(self):
        self.api.routes[f"{BASE}/pulls/85"]["body"] = "Refs #42"
        self.assertEqual(self.process(), [42])
        self.assertEqual([action[0] for action in self.api.writes], ["POST", "PATCH"])

    def test_native_closes_and_unlinked_prs_do_not_trigger(self):
        for body in ["Closes #42", "No issue references", "```md\nRefs #42\n```"]:
            self.api.routes[f"{BASE}/pulls/85"]["body"] = body
            self.assertEqual(self.process(), [])
        self.assertEqual(self.api.writes, [])

    def test_untrusted_non_main_or_failed_run_never_closes(self):
        for field, value in [("head_branch", "feature"),
                             ("conclusion", "failure"),
                             ("event", "pull_request"),
                             ("head_sha", "bad")]:
            original = self.event["workflow_run"][field]
            self.event["workflow_run"][field] = value
            try:
                if field == "head_sha":
                    with self.assertRaises(ContractError):
                        self.process()
                else:
                    self.assertEqual(self.process(), [])
            finally:
                self.event["workflow_run"][field] = original
        self.assertEqual(self.api.writes, [])

    def test_exact_pr_head_ci_required(self):
        path = (f"{BASE}/actions/workflows/ci.yml/runs"
                f"?event=pull_request&head_sha={HEAD}&per_page=100")
        for change in [{"conclusion": "failure"},
                       {"head_sha": "c" * 40},
                       {"pull_requests": [{"number": 86}]}]:
            original = copy.deepcopy(self.api.routes[path]["workflow_runs"][0])
            self.api.routes[path]["workflow_runs"][0].update(change)
            with self.assertRaisesRegex(ContractError, "exact-head"):
                self.process()
            self.api.routes[path]["workflow_runs"][0] = original
        self.assertEqual(self.api.writes, [])

    def test_gaps_and_manual_criteria_block_closure(self):
        original = json.loads(self.manifest.read_text())["issues"][0]["criteria"]
        for kind in ["gap", "manual"]:
            self.write_manifest(original + [{
                "id": "ac_2", "requirement": "Requires physical verification",
                "type": kind, "reason": "Cannot execute on hosted CI",
            }])
            with self.assertRaises(ContractError):
                self.process()
        self.assertEqual(self.api.writes, [])

    def test_refs_with_manual_or_gap_evidence_leave_issue_open(self):
        self.api.routes[f"{BASE}/pulls/85"]["body"] = "Refs #42"
        original = json.loads(self.manifest.read_text())["issues"][0]["criteria"]
        for kind in ["manual", "gap"]:
            self.write_manifest(original + [{
                "id": "ac_2", "requirement": "Real-device verification",
                "type": kind, "reason": "Unverified on hosted CI",
            }])
            self.assertEqual(self.process(), [])
        self.assertEqual(self.api.writes, [])

    def test_refs_with_missing_criterion_leave_issue_open(self):
        self.api.routes[f"{BASE}/pulls/85"]["body"] = "Refs #42"
        self.api.routes[f"{BASE}/issues/42"]["body"] = (
            "## Acceptance criteria\n"
            "- [ ] AC-1: Reject malformed inputs with no side effects.\n"
            "- [ ] AC-2: Reject actions when offline.\n"
            "## CI and validation\nRun issue-specific tests.\n"
        )
        self.assertEqual(self.process(), [])
        self.assertEqual(self.api.writes, [])

    def test_missing_criterion_blocks_closure(self):
        self.api.routes[f"{BASE}/issues/42"]["body"] = (
            "## Acceptance criteria\n"
            "- [ ] AC-1: Reject malformed inputs with no side effects.\n"
            "- [ ] AC-2: Reject actions when offline.\n"
            "## CI and validation\nRun issue-specific tests.\n"
        )
        with self.assertRaisesRegex(ContractError, "differ"):
            self.process()
        self.assertEqual(self.api.writes, [])

    def test_wrong_merge_commit_blocks_closure(self):
        self.api.routes[f"{BASE}/pulls/85"]["merge_commit_sha"] = "c" * 40
        self.assertEqual(self.process(), [])
        self.assertEqual(self.api.writes, [])


if __name__ == "__main__":
    unittest.main()
