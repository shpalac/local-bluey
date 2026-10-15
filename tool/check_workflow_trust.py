#!/usr/bin/env python3
"""Fail closed on privileged untrusted-PR workflow entry points (#599).

This is a static guard, not a replacement for runtime artifact or egress review.
"""
from pathlib import Path
import re
import sys


UNSAFE_TRIGGER = re.compile(r"^\s*(?:-\s*)?pull_request_target\s*:")
INHERITED_SECRETS = re.compile(r"^\s*(?:-\s*)?secrets\s*:\s*inherit\s*(?:#.*)?$")


def check(directory: Path) -> int:
    if not directory.is_dir():
        print("Workflow trust guard: workflow directory missing", file=sys.stderr)
        return 1

    workflows = sorted((*directory.glob("*.yml"), *directory.glob("*.yaml")))
    if not workflows:
        print("Workflow trust guard: no YAML workflows found", file=sys.stderr)
        return 1

    failures = []
    for workflow in workflows:
        try:
            lines = workflow.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError):
            failures.append(f"{workflow.name}: unable to read workflow")
            continue

        for number, line in enumerate(lines, start=1):
            if line.lstrip().startswith("#"):
                continue
            if UNSAFE_TRIGGER.match(line):
                failures.append(
                    f"{workflow.name}:{number}: pull_request_target is forbidden"
                )
            if INHERITED_SECRETS.match(line):
                failures.append(
                    f"{workflow.name}:{number}: inherited secrets are forbidden"
                )

    if failures:
        for failure in failures:
            print(f"Workflow trust guard: {failure}", file=sys.stderr)
        return 1

    print(f"Workflow trust guard: checked {len(workflows)} workflow(s)")
    return 0


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(".github/workflows")
    if len(sys.argv) > 2:
        print("Usage: check_workflow_trust.py [workflows-directory]", file=sys.stderr)
        sys.exit(2)
    sys.exit(check(target))
