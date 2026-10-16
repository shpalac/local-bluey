#!/usr/bin/env python3
"""Enable automatic squash-merge for approved PRs at CI start or success.

Uses the trusted base branch's script and PR metadata only. Never checks out
pull-request code with a write-enabled GitHub Actions token.
"""
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from approved_author_auto_merge import parse_approved_authors
from issue_auto_close import GitHub
from issue_task_ci import ContractError, REPOSITORY

SHA = re.compile(r"^[0-9a-f]{40}$")


def enable_auto_merge(token, node_id):
    payload = {
        "query": (
            "mutation($id: ID!) { enablePullRequestAutoMerge("
            "input: {pullRequestId: $id, mergeMethod: SQUASH}"
            ") { pullRequest { number } } }"
        ),
        "variables": {"id": node_id},
    }
    request = Request("https://api.github.com/graphql",
                      data=json.dumps(payload).encode("utf-8"),
                      headers={
                          "Authorization": f"Bearer {token}",
                          "Content-Type": "application/json",
                          "Accept": "application/vnd.github+json",
                          "User-Agent": "local-bluey-acceptance-auto-merge",
                      })
    try:
        with urlopen(request, timeout=20) as response:
            result = json.load(response)
    except (HTTPError, URLError, TimeoutError, ValueError) as exc:
        raise ContractError(f"Cannot enable PR auto-merge ({type(exc).__name__})") from None
    if result.get("errors") or not result.get("data", {}).get(
            "enablePullRequestAutoMerge", {}).get("pullRequest", {}).get("number"):
        raise ContractError("GitHub rejected auto-merge request")


def eligible_prs(event, repo, client, approved_authors):
    run = event.get("workflow_run", {})
    requested = (event.get("action") == "requested"
                 and run.get("status") in ("queued", "requested", "in_progress"))
    passed = (event.get("action") == "completed"
              and run.get("status") == "completed"
              and run.get("conclusion") == "success")
    if (event.get("repository", {}).get("full_name") != repo
            or run.get("event") != "pull_request"
            or not (requested or passed)
            or run.get("head_repository", {}).get("full_name") != repo):
        return []
    head_sha = run.get("head_sha")
    if not isinstance(head_sha, str) or not SHA.fullmatch(head_sha):
        raise ContractError("invalid checked PR head SHA")
    result = []
    for candidate in run.get("pull_requests", []):
        number = candidate.get("number")
        if type(number) is not int or number < 1:
            continue
        pr = client.request(f"/repos/{repo}/pulls/{number}")
        if (pr.get("state") != "open"
                or pr.get("draft") is not False
                or (pr.get("user") or {}).get("login", "").casefold() not in approved_authors
                or pr.get("base", {}).get("ref") != "main"
                or pr.get("head", {}).get("sha") != head_sha
                or (pr.get("head", {}).get("repo") or {}).get("full_name") != repo):
            continue
        node_id = pr.get("node_id")
        if not isinstance(node_id, str) or not node_id:
            raise ContractError(f"PR #{number}: missing node id")
        if not pr.get("auto_merge"):
            result.append((number, node_id))
    return result


def main():
    try:
        repo = os.environ["GITHUB_REPOSITORY"]
        token = os.environ["GITHUB_TOKEN"]
        if not REPOSITORY.fullmatch(repo):
            raise ContractError("invalid repository identifier")
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(
            encoding="utf-8"
        ))
        client = GitHub(token)
        approved = parse_approved_authors(os.environ.get("APPROVED_PR_AUTHORS", ""))
        for number, node_id in eligible_prs(event, repo, client, approved):
            enable_auto_merge(token, node_id)
            print(f"PR #{number}: approved squash auto-merge queued (required checks apply).")
        return 0
    except (ContractError, KeyError, OSError, ValueError, TypeError) as exc:
        print(f"::error::Auto-merge not enabled: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
