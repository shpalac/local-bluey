#!/usr/bin/env python3
"""Check issue-linked test evidence without claiming manual sign-off.

Only emits bounded identifiers and test filenames; never stores test stdout,
fixture secrets, screenshots or model responses in reports. A passing CI job
means automated tests passed, not that every acceptance criterion is complete.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

SCHEMA_VERSION = 1
STATUS = {"automated": "not_run", "manual": "manual_required", "gap": "not_implemented"}
CASE = re.compile(r"\btest(?:Widgets)?\s*\(\s*(['\"])([^'\"\n]+)\1")
ID = re.compile(r"^[a-z][a-z0-9_]{2,63}$")


class ManifestError(ValueError):
    """A manifest's claimed evidence cannot be trusted."""


def load_manifest(root: Path, source: Path) -> dict:
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ManifestError(f"invalid manifest ({type(exc).__name__})") from None
    if set(data) != {"version", "issues"} or data["version"] != SCHEMA_VERSION:
        raise ManifestError("unknown manifest schema")
    if not isinstance(data["issues"], list) or not data["issues"]:
        raise ManifestError("issues must be a non-empty list")
    seen_issues = set()
    for issue in data["issues"]:
        if not isinstance(issue, dict) or set(issue) != {"number", "title", "criteria"}:
            raise ManifestError("invalid issue record")
        number = issue["number"]
        if type(number) is not int or number <= 0 or number in seen_issues:
            raise ManifestError("invalid or duplicate issue number")
        seen_issues.add(number)
        if not isinstance(issue["title"], str) or not issue["title"].strip():
            raise ManifestError("empty issue title")
        if not isinstance(issue["criteria"], list) or not issue["criteria"]:
            raise ManifestError("issue must declare criteria")
        seen_criteria = set()
        evidence_owners = {}
        for c in issue["criteria"]:
            if not isinstance(c, dict) or not {"id", "requirement", "type"} <= set(c):
                raise ManifestError(f"#{number}: invalid criterion")
            if c["type"] not in STATUS or not isinstance(c["requirement"], str) or not c["requirement"].strip():
                raise ManifestError(f"#{number}: invalid requirement/type")
            identifier = c["id"]
            if not isinstance(identifier, str) or not ID.fullmatch(identifier) or identifier in seen_criteria:
                raise ManifestError(f"#{number}: invalid/duplicate criterion id")
            seen_criteria.add(identifier)
            if c["type"] == "automated":
                if set(c) != {"id", "requirement", "type", "tests"} or not isinstance(c["tests"], list) or not c["tests"]:
                    raise ManifestError(f"#{number}/{identifier}: automated evidence required")
                for test in c["tests"]:
                    if not isinstance(test, dict) or set(test) != {"file", "name"}:
                        raise ManifestError(f"#{number}/{identifier}: invalid test reference")
                    path, name = test["file"], test["name"]
                    if not isinstance(path, str) or not re.fullmatch(r"(?:test|integration_test)/[A-Za-z0-9_/]+_test\.dart", path):
                        raise ManifestError(f"#{number}/{identifier}: unsafe test path")
                    if not isinstance(name, str) or not name or len(name) > 200:
                        raise ManifestError(f"#{number}/{identifier}: invalid test name")
                    candidate = (root / path).resolve()
                    if not candidate.is_relative_to((root / path.split("/")[0]).resolve()) or not candidate.is_file():
                        raise ManifestError(f"#{number}/{identifier}: test file missing or outside repository")
                    source_text = candidate.read_text(encoding="utf-8")
                    if name not in {m.group(2) for m in CASE.finditer(source_text)}:
                        raise ManifestError(f"#{number}/{identifier}: declared test name missing in {path}")
                    evidence_key = (path, name)
                    previous = evidence_owners.setdefault(evidence_key, identifier)
                    if previous != identifier:
                        raise ManifestError(f"#{number}/{identifier}: one named test has duplicate evidence ownership")
            else:
                if set(c) != {"id", "requirement", "type", "reason"} or not isinstance(c["reason"], str) or not c["reason"].strip():
                    raise ManifestError(f"#{number}/{identifier}: explicit gap/manual reason required")
    return data


def expected_tests(issues: list[dict], mode: str = "all") -> dict[str, set[str]]:
    """Derive named test selection solely from validated issue manifests.

    The same planner drives issue-linked PR checks and specialist workflows.
    Unit/integration filtering never silently changes the declared names.
    """
    prefixes = {
        "all": ("test/", "integration_test/"),
        "unit": ("test/",),
        "integration": ("integration_test/",),
    }
    if mode not in prefixes:
        raise ValueError(f"unsupported acceptance test mode: {mode}")
    selected = {}
    for issue in issues:
        for criterion in issue["criteria"]:
            if criterion["type"] != "automated":
                continue
            for case in criterion["tests"]:
                path = case["file"]
                if path.startswith(prefixes[mode]):
                    selected.setdefault(path, set()).add(case["name"])
    return dict(sorted(selected.items()))


def run_suites(expected: dict[str, set[str]], root: Path, timeout: int) -> dict[tuple[str, str], bool]:
    """Require every named case to be observed as successful, not skipped.

    The JSON event protocol binds test IDs to names and testDone outcomes.
    Whole-file nonzero exit or missing machine events fails every reference.
    Raw test messages remain in memory and are never echoed or uploaded.
    """
    result = {}
    for path, names in sorted(expected.items()):
        print(f"Running acceptance suite: {path}", flush=True)
        started = {}
        finished = {}
        passed_file = False
        try:
            outcome = subprocess.run(
                ["flutter", "test", path, "--reporter", "json"],
                cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                timeout=timeout, check=False,
                # Never expose the GitHub API token to untrusted test processes.
                env={k: v for k, v in os.environ.items() if k not in {
                    "GITHUB_TOKEN", "GH_TOKEN", "ACTIONS_RUNTIME_TOKEN"
                }},
            )
            passed_file = outcome.returncode == 0
            for raw in outcome.stdout.splitlines():
                try:
                    event = json.loads(raw)
                except (ValueError, TypeError):
                    continue
                if not isinstance(event, dict):
                    continue
                if event.get("type") == "testStart":
                    test = event.get("test")
                    if isinstance(test, dict) and type(test.get("id")) is int and isinstance(test.get("name"), str):
                        started[test["id"]] = test["name"]
                elif event.get("type") == "testDone":
                    test_id = event.get("testID")
                    finished[test_id] = event.get("result") == "success" and event.get("skipped") is False
        except (OSError, subprocess.TimeoutExpired):
            passed_file = False

        for name in sorted(names):
            matches = [
                test_id for test_id, observed in started.items()
                if observed == name or observed.endswith(" " + name)
            ]
            result[(path, name)] = (
                passed_file and len(matches) == 1 and finished.get(matches[0]) is True
            )
            if not result[(path, name)]:
                print(f"::error file={path}::Named acceptance test missing, skipped, failed or timed out (output withheld)", flush=True)
    return result


def render(data: dict, suites: dict[tuple[str, str], bool] | None) -> tuple[dict, str]:
    report = {"schemaVersion": SCHEMA_VERSION, "issues": [], "automatedSuitesPassed": suites is not None, "issueCompletionCertified": False}
    md = ["# Acceptance evidence", "", "**Important:** CI validates named automated suites only. `manual_required` and `not_implemented` cannot be marked passed by CI or used to auto-close an issue.", ""]
    for issue in data["issues"]:
        rows = []
        for c in issue["criteria"]:
            if c["type"] == "automated":
                files = sorted({t["file"] for t in c["tests"]})
                status = "not_run" if suites is None else ("passed" if all(suites.get((t["file"], t["name"])) is True for t in c["tests"]) else "failed")
                if status == "failed":
                    report["automatedSuitesPassed"] = False
                reason = "Every named case ran successfully and its whole test suite passed" if status == "passed" else "Each named case must run, not skip, and pass"
            else:
                status, reason = STATUS[c["type"]], c["reason"]
                files = []
            rows.append({"id": c["id"], "requirement": c["requirement"], "status": status, "evidenceFiles": files, "reason": reason})
        incomplete = any(row["status"] != "passed" for row in rows)
        report["issues"].append({"number": issue["number"], "title": issue["title"], "acceptanceComplete": not incomplete, "criteria": rows})
        md += [f"## #{issue['number']} — {issue['title']}", "", "| Criterion | Evidence | Result |", "|---|---|---|"]
        for row in rows:
            evidence = ", ".join(f"`{p}`" for p in row["evidenceFiles"]) or row["reason"].replace("|", "\\|")
            md.append(f"| `{row['id']}` — {row['requirement'].replace('|', '\\|')} | {evidence} | **{row['status']}** |")
        md += ["", "**Issue acceptance:** " + ("All declared criteria passed; maintainer review still required" if not incomplete else "Incomplete — do not close automatically"), ""]
    return report, "\n".join(md) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument("--manifest", type=Path, default=Path("docs/acceptance/criteria.json"))
    ap.add_argument("--out-dir", type=Path, default=Path("build/acceptance"))
    ap.add_argument("--run-tests", action="store_true")
    ap.add_argument("--timeout", type=int, default=150)
    args = ap.parse_args(argv)
    root = args.root.resolve()
    if args.timeout < 1 or args.timeout > 300:
        ap.error("--timeout must be between 1 and 300 seconds")
    try:
        data = load_manifest(root, (root / args.manifest).resolve())
    except ManifestError as exc:
        print(f"::error::Acceptance manifest invalid: {exc}", file=sys.stderr)
        return 1
    suites = None
    if args.run_tests:
        suites = run_suites(expected_tests(data["issues"]), root, args.timeout)
    report, markdown = render(data, suites)
    output = (root / args.out_dir).resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "acceptance.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (output / "acceptance.md").write_text(markdown, encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(markdown)
    label = "NOT RUN" if suites is None else ("PASSED" if report["automatedSuitesPassed"] else "FAILED")
    print("Acceptance report written. Automated evidence: " + label + ". Unfinished criteria remain visible.")
    return 0 if suites is None or report["automatedSuitesPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
