#!/usr/bin/env python3
"""Close fully proven issue tasks only after the merged main-branch CI passes.

AutoClose #123 in a merged PR is an intent marker, not a GitHub-native
closing keyword. This script runs from a trusted main-branch workflow_run
with write access; it never checks out or executes a PR branch.
"""
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from issue_task_ci import (
    ContractError, REPOSITORY, select_manifest, validate_issue_body,
    validate_stage,
)

COMMIT = re.compile(r"^[0-9a-f]{40}$")
AUTO_CLOSE = re.compile(r"(?im)^\s*AutoClose\s+#([1-9]\d*)\s*$")
COMMENT_MARKER = "<!-- local-bluey:acceptance-auto-close -->"


class GitHub:
    """Small authenticated GitHub API client; errors never echo responses."""

    def __init__(self, token):
        if not token:
            raise ContractError("missing GitHub token")
        self.token = token

    def request(self, path, method="GET", payload=None):
        if not path.startswith("/repos/"):
            raise ContractError("invalid GitHub API path")
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "local-bluey-issue-auto-close",
            "Authorization": f"Bearer {self.token}",
        }
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = Request("https://api.github.com" + path, data=data,
                          headers=headers, method=method)
        try:
            with urlopen(request, timeout=20) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except (HTTPError, URLError, TimeoutError, ValueError) as exc:
            raise ContractError(f"GitHub API request failed ({type(exc).__name__})") from None


def closing_numbers(body):
    """Only explicit custom markers trigger post-main-CI closure."""
    if not isinstance(body, str):
        return set()
    # Ignore snippets to avoid activating example PR templates.
    body = re.sub(r"(?ms)^\x60\x60\x60.*?^\x60\x60\x60[^\n]*(?:\n|$)", "", body)
    return {int(number) for number in AUTO_CLOSE.findall(body)}


def successful_pr_ci(client, repo, number, head_sha):
    """Require the completed, successful CI workflow for this exact PR head."""
    path = (f"/repos/{repo}/actions/workflows/ci.yml/runs"
            f"?event=pull_request&head_sha={head_sha}&per_page=100")
    runs = client.request(path).get("workflow_runs", [])
    return any(
        run.get("event") == "pull_request"
        and run.get("head_sha") == head_sha
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
        and any(p.get("number") == number for p in run.get("pull_requests", []))
        for run in runs
    )


def verify_acceptance(root, number, body):
    """Fail closed on missing/extra ACs, gaps, manual work or legacy manifests."""
    expected = validate_issue_body(body, number)
    if not expected:
        raise ContractError(f"#{number}: numbered acceptance criteria required")
    path, stage = select_manifest(root, number)
    record = validate_stage(root, number, path, stage, closing=True)
    mapped = {criterion["id"] for criterion in record["criteria"]}
    if mapped != expected:
        raise ContractError(f"#{number}: issue criteria and evidence differ")
    if not all(criterion["type"] == "automated" for criterion in record["criteria"]):
        raise ContractError(f"#{number}: unresolved non-automated criterion")
    return path


def process(event, repo, root, client):
    run = event.get("workflow_run", {})
    if (event.get("repository", {}).get("full_name") != repo
            or run.get("event") != "push"
            or run.get("status") != "completed"
            or run.get("conclusion") != "success"
            or run.get("head_branch") != "main"
            or run.get("head_repository", {}).get("full_name") != repo):
        print("No successful trusted main-branch CI run; nothing to close.")
        return []
    merge_sha = run.get("head_sha", "")
    if not isinstance(merge_sha, str) or not COMMIT.fullmatch(merge_sha):
        raise ContractError("invalid trusted CI commit SHA")

    base = f"/repos/{repo}"
    associated = client.request(f"{base}/commits/{merge_sha}/pulls")
    if not isinstance(associated, list):
        raise ContractError("cannot inspect merged pull requests")
    closed = []
    for candidate in associated:
        number = candidate.get("number")
        if type(number) is not int or number < 1:
            continue
        pr = client.request(f"{base}/pulls/{number}")
        if (not pr.get("merged_at") or pr.get("merge_commit_sha") != merge_sha
                or pr.get("base", {}).get("ref") != "main"):
            continue
        targets = closing_numbers(pr.get("body"))
        if not targets:
            continue
        head_sha = pr.get("head", {}).get("sha", "")
        if not isinstance(head_sha, str) or not COMMIT.fullmatch(head_sha):
            raise ContractError(f"PR #{number}: invalid head SHA")
        if not successful_pr_ci(client, repo, number, head_sha):
            raise ContractError(f"PR #{number}: successful exact-head PR CI not found")

        for issue_number in sorted(targets):
            issue = client.request(f"{base}/issues/{issue_number}")
            if "pull_request" in issue:
                raise ContractError(f"#{issue_number}: target is a pull request")
            if issue.get("state") != "open":
                print(f"#{issue_number}: already closed; no action.")
                continue
            manifest = verify_acceptance(root, issue_number, issue.get("body", ""))
            comments = client.request(
                f"{base}/issues/{issue_number}/comments?per_page=100"
            )
            if not isinstance(comments, list):
                raise ContractError("cannot inspect existing closure comments")
            marker = f"{COMMENT_MARKER} PR #{number} @ {merge_sha}"
            if not any(marker in c.get("body", "") for c in comments
                       if isinstance(c, dict) and isinstance(c.get("body"), str)):
                client.request(f"{base}/issues/{issue_number}/comments", "POST", {
                    "body": (
                        f"{marker}\n"
                        f"Acceptance complete: all numbered criteria have named "
                        f"automated tests in `{manifest.relative_to(root)}`. "
                        f"PR #{number} passed exact-head CI and the merged "
                        f"commit `{merge_sha}` passed main CI. "
                        "No manual or implementation gaps remain in the contract."
                    ),
                })
            client.request(f"{base}/issues/{issue_number}", "PATCH", {
                "state": "closed", "state_reason": "completed",
            })
            closed.append(issue_number)
            print(f"Closed #{issue_number} after successful main CI.")
    return closed


def main():
    try:
        repo = os.environ["GITHUB_REPOSITORY"]
        if not REPOSITORY.fullmatch(repo):
            raise ContractError("invalid repository identifier")
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(
            encoding="utf-8"
        ))
        process(event, repo, Path(__file__).resolve().parent.parent,
                GitHub(os.environ.get("GITHUB_TOKEN", "")))
        return 0
    except (ContractError, OSError, ValueError, KeyError, TypeError) as exc:
        print(f"::error::Issue auto-close blocked: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
