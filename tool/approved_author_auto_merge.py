#!/usr/bin/env python3
"""Queue GitHub squash auto-merge for approved, same-repository PR authors.

This program is invoked from a privileged pull_request_target workflow that
checks out trusted main only. It never executes the pull request's code.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
LOGIN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")
EVENTS = frozenset({"opened", "reopened", "ready_for_review", "synchronize"})


def parse_approved_authors(value):
    """Return normalized exact GitHub logins, rejecting bad configuration."""
    if not isinstance(value, str):
        raise ValueError("Approved authors must be a string")
    authors = set()
    for name in re.split(r"[,\s]+", value.strip()):
        if not name:
            continue
        if not LOGIN.fullmatch(name):
            raise ValueError("Approved authors contains an invalid login")
        authors.add(name.casefold())
    return authors


def eligible_pr_number(event, repository, approved_authors):
    """Check only GitHub-controlled metadata; deny unknown or draft PRs."""
    if not isinstance(event, dict) or event.get("action") not in EVENTS:
        return None
    repo_info = event.get("repository")
    pr = event.get("pull_request")
    if not isinstance(repo_info, dict) or not isinstance(pr, dict):
        return None
    if repo_info.get("full_name") != repository or pr.get("draft") is not False:
        return None

    base = pr.get("base")
    head = pr.get("head")
    user = pr.get("user")
    if not all(isinstance(value, dict) for value in (base, head, user)):
        return None
    head_repo = head.get("repo")
    if not isinstance(head_repo, dict):
        return None
    author = user.get("login")
    number = pr.get("number")
    if (
        base.get("ref") != "main"
        or head_repo.get("full_name") != repository
        or not isinstance(author, str)
        or author.casefold() not in approved_authors
        or type(number) is not int
        or number < 1
    ):
        return None
    return number


def queue_auto_merge(repository, number):
    """Enable GitHub's protected, required-check-aware auto-merge."""
    subprocess.run(
        ["gh", "pr", "merge", str(number), "--repo", repository,
         "--auto", "--squash"],
        check=True,
    )


def main():
    try:
        repository = os.environ["GITHUB_REPOSITORY"]
        if not REPOSITORY.fullmatch(repository):
            raise ValueError("Invalid repository identifier")
        if not os.environ.get("GH_TOKEN"):
            raise ValueError("Missing GitHub token")

        event = json.loads(
            Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8")
        )
        authors = parse_approved_authors(
            os.environ.get("APPROVED_PR_AUTHORS", "")
        )
        number = eligible_pr_number(event, repository, authors)
        if number is None:
            print("Not a ready, same-repo PR from an approved author; skipping.")
            return 0
        queue_auto_merge(repository, number)
        print(f"PR #{number}: GitHub squash auto-merge enabled (required checks apply).")
        return 0
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(
            f"::error::Cannot queue approved PR auto-merge ({type(exc).__name__}).",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
