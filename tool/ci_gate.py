#!/usr/bin/env python3
"""Stable required GitHub status: fail if any selected job failed or was skipped."""
import json
import os
import sys

REQUIRED_WHEN_SELECTED = {
    "static": "static",
    "docs": "docs",
    "acceptance-evidence": "acceptance",
    "test": "test",
    "build-macos": "build_macos",
    "build-ios": "build_ios",
    "simulator": "simulator",
    "android": "android",
    "android-integration": "android_integration",
    "linux": "linux",
}
ALWAYS_REQUIRED = ("security", "pinned-actions")


def failures(plan: dict, jobs: dict) -> list[str]:
    problems = []
    if jobs.get("detect", {}).get("result") != "success":
        problems.append("impact detection did not succeed")
    flags = plan.get("lanes", {})
    if set(flags) != set(REQUIRED_WHEN_SELECTED.values()):
        problems.append("incomplete impact plan")
    for job, lane in REQUIRED_WHEN_SELECTED.items():
        result = jobs.get(job, {}).get("result", "missing")
        expected = flags.get(lane)
        if type(expected) is not bool:
            problems.append(f"{job}: missing or invalid expected flag")
        elif expected and result != "success":
            problems.append(f"{job}: expected success, received {result}")
        elif not expected and result not in ("success", "skipped"):
            problems.append(f"{job}: unexpected result {result}")
    for job in ALWAYS_REQUIRED:
        result = jobs.get(job, {}).get("result", "missing")
        if result != "success":
            problems.append(f"{job}: expected success, received {result}")
    return problems


def main() -> int:
    try:
        plan = json.loads(os.environ["CI_PLAN_JSON"])
        jobs = json.loads(os.environ["NEEDS_JSON"])
        problems = failures(plan, jobs)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"::error::invalid gate inputs: {exc}", file=sys.stderr)
        return 1
    for problem in problems:
        print(f"::error::{problem}", file=sys.stderr)
    if problems:
        return 1
    print("Every selected CI lane passed; non-applicable lanes were skipped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
