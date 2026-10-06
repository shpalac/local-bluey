#!/usr/bin/env python3
"""Scores ocr_bench output against fixture expectations (#213).

Word-level accuracy: fraction of expected words found across the
recognized lines of that fixture. Hebrew words compare as-is; the
comparison is whitespace-token based, which suits both directions.
"""
import json
import sys


def words(s):
    return s.replace("\u05be", " ").split()


def main(results_path, report_path):
    rows = []
    with open(results_path) as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))

    total_expected = 0
    total_found = 0
    report_lines = [
        "# Hebrew/English OCR bench report (#213)",
        "",
        "| fixture | expected words | found | accuracy |",
        "| --- | --- | --- | --- |",
    ]
    for row in rows:
        expected_words = words(row["expected"])
        haystack = " ".join(row["recognized"])
        found = sum(1 for w in expected_words if w in haystack)
        total_expected += len(expected_words)
        total_found += found
        acc = (found / len(expected_words) * 100) if expected_words else 0
        report_lines.append(
            f"| {row['id']} | {len(expected_words)} | {found} | {acc:.0f}% |"
        )
    overall = (total_found / total_expected * 100) if total_expected else 0
    report_lines += [
        "",
        f"**Overall word accuracy: {overall:.1f}%** "
        f"({total_found}/{total_expected} words)",
        "",
        "Raw recognized lines:",
        "",
    ]
    for row in rows:
        report_lines.append(f"- `{row['id']}`: {row['recognized']}")

    with open(report_path, "w") as f:
        f.write("\n".join(report_lines) + "\n")
    print(f"overall {overall:.1f}% -> {report_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: score.py results.jsonl report.md")
    main(sys.argv[1], sys.argv[2])
