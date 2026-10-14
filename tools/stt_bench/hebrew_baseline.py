#!/usr/bin/env python3
"""Deterministic, offline Hebrew STT baseline comparison (BLU-024).

Only text and pre-recorded timings are processed. No microphones, networks,
models or application settings are accessed.
"""
import csv
import json
import re
import statistics
import unicodedata
from pathlib import Path

SUPPORTED_STATES = frozenset({
    "success", "invalid_input", "offline", "timeout",
    "permission_denied", "cancelled", "restart",
})


def normalize(text):
    if not isinstance(text, str):
        raise ValueError("transcript must be a string")
    text = unicodedata.normalize("NFKC", text).casefold()
    text = re.sub(r"[\u0591-\u05c7]", "", text)
    text = re.sub(r"[^\w\s]", " ", text, flags=re.UNICODE)
    return " ".join(text.split())


def distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for i, left in enumerate(reference, 1):
        current = [i]
        for j, right in enumerate(hypothesis, 1):
            current.append(min(
                previous[j] + 1,
                current[-1] + 1,
                previous[j - 1] + (left != right),
            ))
        previous = current
    return previous[-1]


def error_counts(reference, hypothesis):
    reference = normalize(reference)
    hypothesis = normalize(hypothesis)
    words = reference.split()
    chars = list(reference)
    return {
        "word_errors": distance(words, hypothesis.split()),
        "reference_words": len(words),
        "character_errors": distance(chars, list(hypothesis)),
        "reference_characters": len(chars),
    }


def summarize(rows):
    """Compare full clip identity sets, never silently omit failed clips."""
    if not rows:
        raise ValueError("empty benchmark")
    by_backend = {}
    seen = set()
    for row in rows:
        backend = row["backend"]
        clip = row["clip"]
        state = row["state"]
        if not backend or not clip or state not in SUPPORTED_STATES:
            raise ValueError("invalid backend, clip or state")
        identity = (backend, clip)
        if identity in seen:
            raise ValueError("duplicate backend/clip")
        seen.add(identity)
        by_backend.setdefault(backend, []).append(row)
        if state == "success":
            if not isinstance(row.get("hypothesis"), str):
                raise ValueError("successful attempt needs a transcript")
            latency = row.get("latency_ms")
            if type(latency) not in (int, float) or not 0 <= latency < float("inf"):
                raise ValueError("successful attempt needs finite nonnegative latency")
        elif row.get("hypothesis") not in (None, ""):
            raise ValueError("failed attempt must not provide a transcript")

    populations = {backend: {row["clip"] for row in attempts}
                   for backend, attempts in by_backend.items()}
    comparable = len({frozenset(clips) for clips in populations.values()}) == 1
    output = {}
    for backend, attempts in sorted(by_backend.items()):
        totals = dict.fromkeys(
            ("word_errors", "reference_words", "character_errors",
             "reference_characters"), 0)
        latencies = []
        failures = {}
        for row in attempts:
            if row["state"] != "success":
                failures[row["state"]] = failures.get(row["state"], 0) + 1
                continue
            counts = error_counts(row["reference"], row["hypothesis"])
            for key, value in counts.items():
                totals[key] += value
            latencies.append(row["latency_ms"])
        complete = comparable and not failures and len(latencies) == len(attempts)
        output[backend] = {
            "attempted": len(attempts),
            "complete": complete,
            "failures": failures,
            "wer": totals["word_errors"] / totals["reference_words"]
                   if complete and totals["reference_words"] else None,
            "cer": totals["character_errors"] / totals["reference_characters"]
                   if complete and totals["reference_characters"] else None,
            "p50_latency_ms": statistics.median(latencies) if complete else None,
            "clips": sorted(populations[backend]),
        }
    return output


def load_csv(path):
    with Path(path).open(newline="", encoding="utf-8") as handle:
        return [
            {**row, "latency_ms": float(row["latency_ms"])
             if row["latency_ms"] else None}
            for row in csv.DictReader(handle)
        ]


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path, help="Consented text-only CSV input")
    args = parser.parse_args()
    print(json.dumps(summarize(load_csv(args.csv)), ensure_ascii=False,
                     sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
