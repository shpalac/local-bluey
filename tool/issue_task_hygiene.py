#!/usr/bin/env python3
"""Flag newly created or edited issues that lack an actionable task contract."""
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from issue_task_ci import ContractError, REPOSITORY, validate_issue_body
from runner_only_issue_contract import validate_runner_only_contract

MARKER = "<!-- local-bluey:task-contract -->"


def github_request(url: str, token: str, payload: dict | None = None):
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "local-bluey-issue-contract",
        "Authorization": f"Bearer {token}",
    }
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(url, headers=headers, data=data)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    with urlopen(request, timeout=15) as response:
        return json.load(response)


def record_missing_contract(repository: str, number: int, token: str,
                            reason: str, request=github_request) -> bool:
    """Post at most one issue comment; never interpolate untrusted body data."""
    if not REPOSITORY.fullmatch(repository) or not token or number < 1:
        raise ContractError("invalid GitHub issue context")
    url = f"https://api.github.com/repos/{repository}/issues/{number}/comments"
    comments = request(url + "?per_page=100", token)
    if not isinstance(comments, list):
        raise ContractError("cannot inspect existing contract comments")
    if any(MARKER in comment.get("body", "") for comment in comments
           if isinstance(comment, dict) and isinstance(comment.get("body"), str)):
        return False
    request(url, token, {
        "body": (
            f"{MARKER}\n"
            "This issue needs an actionable task contract before implementation:\n\n"
            "- A **## Acceptance criteria** section with measurable checkboxes\n"
            "- A **## CI and validation** section with targeted temporary tests\n"
            "- A hosted runner and named automated test plan per AC\n"
            "- Explicit runner-only scope, non-goals and definition of done\n\n"
            "Use the repository Task issue template and "
            "docs/acceptance/TASK_LIFECYCLE.md.\n\n"
            f"Validation: {reason}"
        ),
    })
    return True


def main() -> int:
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        issue = event["issue"]
        number = issue["number"]
        body = issue.get("body") or ""
        if not isinstance(number, int) or not isinstance(body, str):
            raise ContractError("invalid issue event")
        criteria = validate_issue_body(body, number)
        # Preserve migration of older issues, but never accept a newly opened
        # unnumbered task that could not obtain exact AC-to-test coverage.
        if event.get("action") == "opened":
            if not criteria:
                raise ContractError(
                    f"#{number}: new issues require numbered AC-1:, AC-2:, ... criteria"
                )
            validate_runner_only_contract(body, number)
        print(f"#{number}: acceptance criteria and CI plan present.")
        return 0
    except ContractError as exc:
        print(f"::error::{exc}", file=sys.stderr)
        try:
            if record_missing_contract(
                os.environ["GITHUB_REPOSITORY"], number,
                os.environ["GITHUB_TOKEN"], str(exc)
            ):
                print("Posted a task-contract remediation comment.")
        except (HTTPError, URLError, KeyError, ContractError, TimeoutError, ValueError) as api_exc:
            print(f"::error::Unable to post task feedback ({type(api_exc).__name__})",
                  file=sys.stderr)
        return 1
    except (KeyError, OSError, ValueError, TypeError) as exc:
        print(f"::error::Cannot read issue event ({type(exc).__name__})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
