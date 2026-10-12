#!/usr/bin/env python3
"""Enforce per-issue acceptance evidence on linked pull requests.

A temporary issue manifest runs targeted tests during implementation. Its
permanent replacement must contain end-to-end coverage before a PR can use
a closing keyword. This gate never certifies human-only or hardware checks.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import acceptance_criteria as acceptance

REFERENCE = re.compile(
    r"(?i)\b(closes?|fix(?:es|ed)?|resolves?|refs?)\s+#([1-9]\d*)"
)
ACCEPTANCE_HEADING = re.compile(
    r"(?ims)^##\s+Acceptance criteria\s*$([\s\S]*?)(?=^##\s+|\Z)"
)
CHECKBOX = re.compile(r"(?m)^\s*-\s*\[[ xX]\]\s+(.{10,})$")
VALIDATION_HEADING = re.compile(
    r"(?im)^##\s+(?:CI|GitHub Actions|Automated|Test|Validation)"
)
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


class ContractError(ValueError):
    """An issue cannot be certified from the provided evidence."""


def linked_issues(body: str) -> dict[int, bool]:
    """Return {issue number: requests closing} from explicit PR references."""
    found = {}
    for kind, raw_number in REFERENCE.findall(body):
        number = int(raw_number)
        closing = kind.lower().startswith(("close", "fix", "resolve"))
        found[number] = found.get(number, False) or closing
    return found


def validate_issue_body(body: str, number: int) -> set[str]:
    """Return exact AC identifiers for numbered checklists.

    Existing backlog items without AC numbering can still reference legacy
    evidence during migration, but cannot be auto-closed until normalized.
    """
    section = ACCEPTANCE_HEADING.search(body)
    if not section:
        raise ContractError(f"#{number}: missing Acceptance criteria section")
    items = CHECKBOX.findall(section.group(1))
    if not items:
        raise ContractError(f"#{number}: missing testable Acceptance criteria checklist")
    if not VALIDATION_HEADING.search(body):
        raise ContractError(f"#{number}: missing CI / automated validation plan")
    ids = []
    for item in items:
        match = re.match(r"(?i)AC-([1-9]\d*):\s+", item)
        if match:
            ids.append(f"ac_{int(match.group(1))}")
    if ids and (len(ids) != len(items) or len(ids) != len(set(ids))):
        raise ContractError(
            f"#{number}: number every criterion uniquely as AC-1:, AC-2:, ..."
        )
    return set(ids)


def get_issue_body(repository: str, number: int, token: str) -> str:
    if not REPOSITORY.fullmatch(repository):
        raise ContractError("invalid repository identifier")
    url = f"https://api.github.com/repos/{repository}/issues/{number}"
    headers = {"Accept": "application/vnd.github+json",
               "User-Agent": "local-bluey-acceptance-ci"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=15) as response:
            issue = json.load(response)
    except (HTTPError, URLError, TimeoutError, ValueError) as exc:
        raise ContractError(f"#{number}: cannot read issue ({type(exc).__name__})") from None
    if "pull_request" in issue:
        raise ContractError(f"#{number}: reference is a pull request, not an issue")
    if not isinstance(issue.get("body"), str):
        raise ContractError(f"#{number}: issue body unavailable")
    return issue["body"]


def select_manifest(root: Path, number: int) -> tuple[Path, str]:
    """Prefer an explicit permanent contract over temporary and legacy maps."""
    candidates = [
        (root / f"docs/acceptance/permanent/issue-{number}.json", "permanent"),
        (root / f"docs/acceptance/temporary/issue-{number}.json", "temporary"),
        (root / f"docs/acceptance/issue-{number}.json", "legacy"),
        (root / "docs/acceptance/criteria.json", "legacy"),
    ]
    for path, stage in candidates:
        if not path.is_file():
            continue
        try:
            data = acceptance.load_manifest(root, path)
        except acceptance.ManifestError as exc:
            raise ContractError(f"{path.relative_to(root)}: {exc}") from None
        if any(issue["number"] == number for issue in data["issues"]):
            return path, stage
    raise ContractError(
        f"#{number}: missing issue-specific acceptance manifest. "
        f"Add docs/acceptance/temporary/issue-{number}.json"
    )


def issue_record(root: Path, path: Path, number: int) -> dict:
    data = acceptance.load_manifest(root, path)
    return next(issue for issue in data["issues"] if issue["number"] == number)


def validate_stage(root: Path, number: int, path: Path,
                   stage: str, closing: bool) -> dict:
    record = issue_record(root, path, number)
    criteria = record["criteria"]
    automated = [item for item in criteria if item["type"] == "automated"]
    if not automated:
        raise ContractError(f"#{number}: no executable acceptance tests")
    if stage == "temporary":
        if any(test["file"].startswith("integration_test/")
               for item in automated for test in item["tests"]):
            raise ContractError(f"#{number}: temporary tests must be under test/")
        if (root / f"docs/acceptance/permanent/issue-{number}.json").exists():
            raise ContractError(f"#{number}: remove temporary manifest after promotion")
    if stage == "permanent":
        if not any(test["file"].startswith("integration_test/")
                   for item in automated for test in item["tests"]):
            raise ContractError(
                f"#{number}: permanent manifest needs named integration_test/ coverage"
            )
        if (root / f"docs/acceptance/temporary/issue-{number}.json").exists():
            raise ContractError(
                f"#{number}: remove temporary manifest after permanent coverage is added"
            )
    if closing:
        if stage != "permanent":
            raise ContractError(
                f"#{number}: use Refs until permanent feature integration coverage exists"
            )
        if any(item["type"] == "gap" for item in criteria):
            raise ContractError(f"#{number}: outstanding implementation gaps")
        if any(item["type"] == "manual" for item in criteria):
            raise ContractError(
                f"#{number}: manual criteria require separate maintainer verification; "
                "do not auto-close this issue"
            )
    return record


def expected_tests(records: list[dict], mode: str) -> dict[str, set[str]]:
    prefix = "integration_test/" if mode == "integration" else "test/"
    expected = {}
    for record in records:
        for criterion in record["criteria"]:
            if criterion["type"] != "automated":
                continue
            for test in criterion["tests"]:
                if test["file"].startswith(prefix):
                    expected.setdefault(test["file"], set()).add(test["name"])
    return expected


def check(root: Path, repository: str, body: str, token: str, mode: str,
          issue_fetcher=get_issue_body, runner=acceptance.run_suites) -> bool:
    refs = linked_issues(body)
    if not refs:
        print("No issue references in PR; regular CI still runs.")
        return True
    records = []
    for number, closing in sorted(refs.items()):
        issue_body = issue_fetcher(repository, number, token)
        acceptance_ids = validate_issue_body(issue_body, number)
        path, stage = select_manifest(root, number)
        record = validate_stage(root, number, path, stage, closing)
        if closing and not acceptance_ids:
            raise ContractError(f"#{number}: number all acceptance criteria as AC-1:, AC-2:, ...")
        # Older baseline maps predate AC numbering; allow Refs during migration.
        # New temporary/permanent contracts must map every numbered item.
        if acceptance_ids and stage != "legacy":
            mapped_ids = {criterion["id"] for criterion in record["criteria"]}
            if not acceptance_ids.issubset(mapped_ids):
                missing = ", ".join(sorted(acceptance_ids - mapped_ids))
                raise ContractError(f"#{number}: acceptance criteria missing test mappings: {missing}")
        records.append(record)
        print(f"#{number}: {stage} acceptance contract ({path.relative_to(root)})")
    tests = expected_tests(records, mode)
    if tests:
        results = runner(tests, root, 240)
        if not all(results.values()) or len(results) != sum(map(len, tests.values())):
            print("Issue-specific acceptance tests failed or were skipped.")
            return False
        print(f"Verified {len(results)} named {mode} acceptance tests.")
    else:
        print(f"No {mode} acceptance tests required for these issues.")
    if mode == "unit" and any(
        item["type"] in {"manual", "gap"} for rec in records for item in rec["criteria"]
    ):
        print("INCOMPLETE: manual reviews and unimplemented criteria are not CI passes.")
    return True


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--event", type=Path,
                        default=Path(os.environ.get("GITHUB_EVENT_PATH", "/dev/null")))
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--mode", choices=["unit", "integration"], default="unit")
    args = parser.parse_args(argv)
    try:
        event = json.loads(args.event.read_text(encoding="utf-8"))
        if not isinstance(event, dict):
            raise ContractError("invalid event payload")
        pr = event.get("pull_request")
        if not isinstance(pr, dict):
            print("Not a pull request; existing repository checks apply.")
            return 0
        body = pr.get("body") or ""
        if not isinstance(body, str):
            raise ContractError("invalid pull request body")
        passed = check(args.root.resolve(), args.repo, body,
                       os.environ.get("GITHUB_TOKEN", ""), args.mode)
        return 0 if passed else 1
    except (ContractError, acceptance.ManifestError, OSError, ValueError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
