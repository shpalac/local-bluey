#!/usr/bin/env python3
"""BLU-001..003 acceptance gate with exact, honest per-issue evidence.

Reuses the existing manifest validator/executor. No test is marked as passed
unless its named Flutter test ran successfully. Native/manual gaps remain
incomplete in reports and never become implicit approval.
"""
import argparse
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

import acceptance_criteria as acceptance

ISSUES = (554, 555, 556)
REQUIRED_AC = frozenset({"ac_1", "ac_2", "ac_3", "ac_4"})


def load_contracts(root: Path) -> dict:
    """Validate that each numbered issue criterion is represented once."""
    issue_records = []
    for number in ISSUES:
        path = root / f"docs/acceptance/issue-{number}.json"
        data = acceptance.load_manifest(root, path)
        if len(data["issues"]) != 1 or data["issues"][0]["number"] != number:
            raise acceptance.ManifestError(
                f"issue-{number}.json must contain only issue #{number}"
            )
        issue = data["issues"][0]
        types = {criterion["id"]: criterion["type"] for criterion in issue["criteria"]}
        missing = REQUIRED_AC - types.keys()
        if missing:
            raise acceptance.ManifestError(
                f"#{number}: no evidence record for {', '.join(sorted(missing))}"
            )
        if not any(kind == "automated" for kind in types.values()):
            raise acceptance.ManifestError(f"#{number}: no executable acceptance evidence")
        issue_records.append(issue)

    # These conditions must not silently disappear or be declared automated
    # until verified native work and explicit human sign-off exist.
    required_non_automated = {
        554: {"ac_1": "manual", "ac_3": "manual", "ac_4": "manual"},
        555: {"ac_4": "manual", "migration_review": "manual"},
        556: {"ac_3": "gap", "ac_4": "manual", "native_privacy_review": "manual"},
    }
    for record in issue_records:
        number = record["number"]
        by_id = {c["id"]: c["type"] for c in record["criteria"]}
        for key, expected in required_non_automated[number].items():
            if by_id.get(key) != expected:
                raise acceptance.ManifestError(
                    f"#{number}/{key}: expected {expected} until verified evidence exists"
                )
    return {"version": acceptance.SCHEMA_VERSION, "issues": issue_records}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--out-dir", type=Path, default=Path("build/acceptance/blu-001-003"))
    parser.add_argument("--run-tests", action="store_true")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        combined = load_contracts(root)
        with TemporaryDirectory(prefix="bluey-acceptance-") as directory:
            manifest = Path(directory) / "blu-001-003.json"
            manifest.write_text(json.dumps(combined, ensure_ascii=False), encoding="utf-8")
            flags = [
                "--root", str(root),
                "--manifest", str(manifest),
                "--out-dir", str(args.out_dir),
            ]
            if args.run_tests:
                flags.append("--run-tests")
            return acceptance.main(flags)
    except acceptance.ManifestError as exc:
        print(f"::error::BLU-001..003 acceptance contract: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
