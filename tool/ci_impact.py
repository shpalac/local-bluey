#!/usr/bin/env python3
"""Conservative pull-request impact planner for the Flutter CI lanes.

Unknown paths and shared runtime changes run the full suite. Isolated Dart
modules may select individual tests only when the reverse import graph proves
coverage and no application entrypoint depends on them. Changes to a selected
set of compatibility workflows avoid unrelated native lanes.
Full regression continues on main, with a separate weekly security schedule.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

DART_DEPENDENCY = re.compile(r"""(?:import|export|part)\s+['"]([^'"]+\.dart)['"]""")
TEST_SUFFIX = "_test.dart"
LANES = (
    "static", "docs", "acceptance", "test", "build_macos", "build_ios",
    "simulator", "android", "android_integration", "linux",
)
PLATFORMS = {
    "android/": ("android", "android_integration"),
    "ios/": ("build_ios", "simulator"),
    "macos/": ("build_macos",),
    "linux/": ("linux",),
}
FULL_INPUTS = {
    ".flutter-version", "pubspec.yaml", "pubspec.lock",
    "analysis_options.yaml", "build.yaml",
}
DOCUMENT_NAMES = {"README.md", "CONTRIBUTING.md", "LICENSE", "CHANGELOG.md"}
RUNTIME_ENTRYPOINTS = {"lib/main.dart", "lib/app.dart"}
# These legacy workflows retain their PR check names, but their CI responsibilities
# are already covered by the central gate or their own targeted job.
ISOLATED_WORKFLOW_LANES = {
    ".github/workflows/pr-fast-ci.yml": (),
    ".github/workflows/macos-native-build-lane.yml": ("build_macos",),
    ".github/workflows/temp-issue-596.yml": ("build_ios", "simulator"),
    ".github/workflows/temp-issue-580.yml": ("test",),
    ".github/workflows/temp-issue-590.yml": ("test",),
    ".github/workflows/windows-ci-lane.yml": ("test",),
    ".github/workflows/website.yml": (),
}
# Unit tests for this routing mechanism still run in detect on every PR.
ISOLATED_TOOL_FILES = {
    "tool/test_ci_impact.py", "tool/test_ci_consolidation.py",
    "tool/ci_metrics.py", "tool/test_ci_metrics.py",
}


def changed_files(base_sha: str, root: Path) -> list[str]:
    """Diff the PR merge checkout against the event's trusted base SHA."""
    if not re.fullmatch(r"[0-9a-fA-F]{40}", base_sha):
        raise ValueError("invalid or missing PR base SHA")
    result = subprocess.run(
        ["git", "diff", "--name-only", "-z", "--no-ext-diff", base_sha, "HEAD", "--"],
        cwd=root, check=True, capture_output=True, timeout=30,
    )
    return sorted({part.decode("utf-8") for part in result.stdout.split(b"\0") if part})


def is_document(path: str) -> bool:
    return (
        path in DOCUMENT_NAMES
        or path.startswith("docs/")
        or path.endswith(".md")
    )


def is_workflow_model(path: str) -> bool:
    return path.startswith("lib/workflows/") and path.endswith(".dart")


def _resolve_dart_dependency(root: Path, source: Path, uri: str) -> Path | None:
    if uri.startswith("package:local_bluey/"):
        candidate = root / "lib" / uri.removeprefix("package:local_bluey/")
    elif uri.startswith(("dart:", "package:")):
        return None
    else:
        candidate = source.parent / uri
    resolved = candidate.resolve()
    if resolved.is_relative_to(root.resolve()) and resolved.suffix == ".dart":
        return resolved
    return None


def impacted_tests(root: Path, paths: list[str]) -> list[str] | None:
    """Reverse-walk Dart imports, failing closed for unmapped source changes.

    None means full Flutter tests. An explicit list means a narrow, verifiable
    set of tests. Renames/deletions and test helpers also fall back to full.
    """
    sources = [p for p in paths if p.startswith("lib/") and p.endswith(".dart")]
    test_changes = [p for p in paths if p.startswith("test/")]
    if any(p in RUNTIME_ENTRYPOINTS for p in sources):
        return None
    if any(not p.endswith(TEST_SUFFIX) for p in test_changes):
        return None

    tests = set()
    for path in test_changes:
        if not (root / path).is_file():
            return None
        tests.add(path)

    if sources:
        graph: dict[Path, set[Path]] = {}
        for folder in ("lib", "test", "integration_test"):
            for file in (root / folder).rglob("*.dart"):
                try:
                    imports = DART_DEPENDENCY.findall(file.read_text(encoding="utf-8"))
                except (OSError, UnicodeError):
                    return None
                for uri in imports:
                    dependency = _resolve_dart_dependency(root, file, uri)
                    if dependency is not None:
                        graph.setdefault(dependency, set()).add(file.resolve())

        for source in sources:
            changed = (root / source).resolve()
            if not changed.is_file():
                return None
            queue = [changed]
            seen = {changed}
            found = False
            while queue:
                for dependent in graph.get(queue.pop(), ()):
                    if dependent in seen:
                        continue
                    seen.add(dependent)
                    queue.append(dependent)
                    relative = dependent.relative_to(root.resolve()).as_posix()
                    # A runtime-reachable source can affect application wiring even
                    # when its unit tests import only a subset of that wiring.
                    if not is_workflow_model(source) and (
                        relative in RUNTIME_ENTRYPOINTS
                        or relative.startswith("integration_test/")
                    ):
                        return None
                    if relative.startswith("test/") and relative.endswith(TEST_SUFFIX):
                        tests.add(relative)
                        found = True
            if not found:
                return None

    return sorted(tests) if tests else None


def plan(paths: list[str], event_name: str, root: Path) -> dict:
    """Return the jobs required to verify this change, or full on uncertainty."""
    normalized = sorted(set(paths))
    flags = {name: False for name in LANES}
    run_full = event_name != "pull_request" or not normalized

    for path in normalized:
        parts = PurePosixPath(path).parts
        if (not parts or path.startswith("/") or ".." in parts
                or "\\" in path or "\n" in path):
            run_full = True
            break
        if path in FULL_INPUTS or path.startswith("integration_test/"):
            run_full = True
            continue
        if path in ISOLATED_WORKFLOW_LANES:
            for lane in ISOLATED_WORKFLOW_LANES[path]:
                flags[lane] = True
            continue
        if path in ISOLATED_TOOL_FILES:
            if path in ("tool/ci_metrics.py", "tool/test_ci_metrics.py"):
                flags["static"] = True
            continue
        if path.startswith((".github/", "tool/")):
            # Unknown workflow or tooling changes can modify CI behavior.
            run_full = True
            continue
        if path.startswith("lib/"):
            flags.update(static=True, test=True, acceptance=True)
            if not path.endswith(".dart") or path in RUNTIME_ENTRYPOINTS:
                run_full = True
            continue
        if path.startswith("test/"):
            flags.update(static=True, test=True, acceptance=True)
            continue
        if path in ("android", "ios", "macos", "linux"):
            run_full = True
            continue
        matched_platform = next((prefix for prefix in PLATFORMS if path.startswith(prefix)), None)
        if matched_platform:
            flags.update(static=True, test=True, acceptance=True)
            for lane in PLATFORMS[matched_platform]:
                flags[lane] = True
            continue
        if path.startswith("docs/acceptance/") or path == "docs/ACCEPTANCE_MAP.md":
            flags["acceptance"] = True
            continue
        if is_document(path):
            continue
        # Unrecognized file, symlink or generated code: do not silently skip.
        run_full = True

    # Every PR needs an acceptance result, including docs-only changes and
    # a PR body-only edit adding an AutoClose marker.
    if event_name == "pull_request":
        flags["acceptance"] = True

    selected_tests = None if run_full else impacted_tests(root, normalized)
    # For non-workflow production code, a missing dependency/test mapping or
    # application-entrypoint reachability must preserve full CI behavior.
    if not run_full and selected_tests is None and any(
        path.startswith("lib/") and not is_workflow_model(path)
        for path in normalized
    ):
        run_full = True
    if run_full:
        flags = dict.fromkeys(LANES, True)
    elif any(path.startswith("lib/") for path in normalized):
        flags["docs"] = True

    return {
        "lanes": flags,
        "full_tests": run_full or (flags["test"] and selected_tests is None),
        "test_files": [] if selected_tests is None else selected_tests,
        "android_matrix": [29, 34] if run_full else [34],
        "changed_files": normalized,
        "full_ci": run_full,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--event-name", default=os.environ.get("GITHUB_EVENT_NAME", ""))
    parser.add_argument("--base-sha", default=os.environ.get("PR_BASE_SHA", ""))
    parser.add_argument("--changed-file", action="append")
    parser.add_argument("--output", type=Path, default=Path(os.environ["GITHUB_OUTPUT"]) if "GITHUB_OUTPUT" in os.environ else None)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        paths = (args.changed_file if args.changed_file is not None else
                 changed_files(args.base_sha, root) if args.event_name == "pull_request" else [])
        result = plan(paths, args.event_name, root)
        serialized = json.dumps(result, separators=(",", ":"), sort_keys=True)
        print(serialized)
        if args.output:
            with args.output.open("a", encoding="utf-8") as output:
                output.write(f"plan={serialized}\n")
                for name, enabled in result["lanes"].items():
                    output.write(f"{name}={str(enabled).lower()}\n")
                output.write(f"full_tests={str(result['full_tests']).lower()}\n")
                output.write(f"test_files={json.dumps(result['test_files'], separators=(',', ':'))}\n")
                output.write(f"android_matrix={json.dumps(result['android_matrix'], separators=(',', ':'))}\n")
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"::error::CI impact planning failed: {exc}", file=sys.stderr)
        # Never produce a false green plan. GitHub fails the detect job and gate.
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
