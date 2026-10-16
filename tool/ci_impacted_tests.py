#!/usr/bin/env python3
"""Validate selected Dart test files before a single concurrent Flutter run."""
import argparse
import json
import os
from pathlib import Path
import re
import sys

TEST_PATH = re.compile(r"test/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+_test\.dart")


def select_files(encoded: str, root: Path) -> list[str]:
    try:
        decoded = json.loads(encoded)
    except (ValueError, TypeError):
        raise ValueError("impact plan must contain a JSON array") from None
    if not isinstance(decoded, list) or not decoded:
        raise ValueError("impacted test selection is empty or invalid")
    if any(not isinstance(path, str) or not TEST_PATH.fullmatch(path)
           for path in decoded):
        raise ValueError("impact plan includes an unsafe test filename")
    if len(decoded) != len(set(decoded)):
        raise ValueError("impact plan contains duplicate test filenames")

    test_root = (root / "test").resolve()
    for path in decoded:
        file = (root / path).resolve()
        if not file.is_relative_to(test_root) or not file.is_file():
            raise ValueError("impacted test file missing or escapes test root")
    return sorted(decoded)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path,
                        default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--test-files", default=os.environ.get("TEST_FILES", ""))
    args = parser.parse_args(argv)
    try:
        files = select_files(args.test_files, args.root.resolve())
        args.output.write_text("\n".join(files) + "\n", encoding="utf-8")
    except (OSError, ValueError) as error:
        print(f"::error::Impacted test selection failed: {error}", file=sys.stderr)
        return 1
    print(f"Selected {len(files)} impacted test files for concurrent Flutter execution.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
