#!/usr/bin/env python3
"""Score benchmark runs: normalized Hebrew WER/CER + latency stats (#195, #270).

Usage: wer.py RESULTS_DIR [refs.csv]
refs.csv rows: filename,transcript  (filename without directory)
Requires: pip install jiwer

Every attempt in timings.csv is reconciled against its reference and its
transcript. A backend that failed some clips is reported as INCOMPLETE and is
not comparable with a backend that finished the same set.
"""
import csv, json, os, re, sys, unicodedata

def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).lower()
    # strip nikud, punctuation, collapse whitespace
    s = re.sub(r"[\u0591-\u05C7]", "", s)
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    return " ".join(s.split())

def jiwer_metrics(ref, hyp):
    try:
        import jiwer
    except ImportError:
        sys.exit("pip install jiwer")
    return jiwer.wer(ref, hyp), jiwer.cer(ref, hyp)

def load_refs(path):
    if not os.path.exists(path):
        sys.exit(f"refs.csv not found at {path}")
    refs = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            if row and not row[0].startswith("#") and len(row) > 1:
                refs[row[0].strip()] = row[1].strip()
    if not refs:
        sys.exit(f"no reference transcripts in {path}")
    return refs

def load_attempts(out):
    """One dict per attempted (backend, clip), from timings.csv."""
    tfile = os.path.join(out, "timings.csv")
    if not os.path.exists(tfile):
        sys.exit(f"no timings.csv in {out}: nothing was attempted")
    attempts = []
    with open(tfile, newline="") as f:
        for r in csv.DictReader(f):
            status = (r.get("exit_status") or "").strip()
            attempts.append({
                "backend": r["backend"], "clip": r["clip"],
                "latency": int(r["latency_ms"] or 0),
                "rss": int(r["peak_rss_bytes"] or 0),
                # Older runs have no exit_status column: unknown, not success.
                "exit": int(status) if status.lstrip("-").isdigit() else None,
            })
    if not attempts:
        sys.exit(f"timings.csv in {out} has no attempts: empty evaluation set")
    return attempts

def pct(sorted_vals, q):
    return sorted_vals[min(len(sorted_vals) - 1, int(len(sorted_vals) * q))] if sorted_vals else None

def score(out, refs, metrics=jiwer_metrics):
    attempts = load_attempts(out)
    by_backend = {}
    for a in attempts:
        a["hyp_path"] = os.path.join(out, f"{a['backend']}--{a['clip']}.txt")
        by_backend.setdefault(a["backend"], []).append(a)
    manifest_path = os.path.join(out, "expected.json")
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            expected = json.load(f)
        expected_clips = set(expected["clips"])
        expected_backends = set(expected["backends"])
        if not expected_clips or not expected_backends:
            sys.exit("empty expected backend/clip set")
        for backend in expected_backends:
            by_backend.setdefault(backend, [])
    else:
        # Historical runs have no manifest: compare identities, never counts.
        expected_clips = {a["clip"] for a in attempts}
        expected_backends = set(by_backend)
    results, problems = [], []
    for backend, items in sorted(by_backend.items()):
        ok, failed, pairs = [], [], []
        for a in items:
            has_out = os.path.exists(a["hyp_path"])
            if a["exit"] == 0 and has_out:
                ok.append(a)
            else:
                why = ("exit status unknown (no exit_status column)" if a["exit"] is None
                       else f"exit {a['exit']}" if a["exit"] != 0 else "no transcript written")
                if a["exit"] not in (None, 0) and has_out:
                    why += ", partial output ignored"
                failed.append(a)
                problems.append(f"{backend} / {a['clip']}: {why}")
        for a in ok:
            if a["clip"] not in refs:
                problems.append(f"{backend} / {a['clip']}: no reference, not scored")
                continue
            with open(a["hyp_path"], encoding="utf-8") as f:
                pairs.append((refs[a["clip"]], f.read()))
        wer = cer = None
        if pairs:
            wer, cer = metrics([normalize(r) for r, _ in pairs],
                               [normalize(h) for _, h in pairs])
        lat_ok = sorted(a["latency"] for a in ok)
        lat_bad = sorted(a["latency"] for a in failed)
        actual_clips = {a["clip"] for a in items}
        population_matches = (actual_clips == expected_clips and
                              len(items) == len(actual_clips) and
                              backend in expected_backends)
        if not population_matches:
            problems.append(f"{backend}: evaluation population mismatch; "
                            f"missing clips {sorted(expected_clips - actual_clips)}, "
                            f"unexpected clips {sorted(actual_clips - expected_clips)}; "
                            "duplicate attempts or unselected backend also invalidate comparison")
        complete = population_matches and not failed and len(pairs) == len(items)
        results.append({
            "backend": backend, "attempted": len(items), "succeeded": len(ok),
            "failed": len(failed), "scored": len(pairs), "wer": wer, "cer": cer,
            "p50": pct(lat_ok, 0.5), "p95": pct(lat_ok, 0.95),
            "fail_p50": pct(lat_bad, 0.5),
            "rss": max((a["rss"] for a in items), default=0),
            "complete": complete, "clips": sorted(actual_clips),
        })
    return results, problems

def render(results, problems):
    fmt = lambda v, p=3: "n/a" if v is None else (f"{v:.{p}f}" if isinstance(v, float) else str(v))
    lines = ["| Backend | Attempted | Succeeded | Failed | Scored | WER | CER | "
             "p50 ok ms | p95 ok ms | p50 failed ms | Peak RSS MB | Result |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in results:
        status = "complete" if r["complete"] else "INCOMPLETE - not comparable"
        lines.append(
            f"| {r['backend']} | {r['attempted']} | {r['succeeded']} | {r['failed']} | "
            f"{r['scored']} | {fmt(r['wer'])} | {fmt(r['cer'])} | {fmt(r['p50'])} | "
            f"{fmt(r['p95'])} | {fmt(r['fail_p50'])} | {r['rss'] // 1048576} | {status} |")
    if any(not r["complete"] for r in results):
        lines += ["", "**Caveat:** at least one backend did not finish the full evaluation set. "
                  "WER/CER cover only its successful clips and must not be ranked against "
                  "a complete backend. Latency columns use successful attempts only."]
    if len({tuple(r["clips"]) for r in results}) > 1:
        lines += ["", "**Caveat:** backends attempted different clip identities; equal counts do not establish comparable populations."]
    if problems:
        lines += ["", "Problems:"] + [f"- {p}" for p in problems]
    return "\n".join(lines) + "\n"

def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out, refs_path = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
    if refs_path is None:
        manifest_path = os.path.join(out, "expected.json")
        if os.path.exists(manifest_path):
            with open(manifest_path, encoding="utf-8") as f:
                refs_path = json.load(f).get("refs_path")
        if refs_path is None:
            sys.exit("reference path required for legacy runs: wer.py RESULTS_DIR REFS.csv")
    refs = load_refs(refs_path)
    missing = {a["clip"] for a in load_attempts(out)} - set(refs)
    manifest_path = os.path.join(out, "expected.json")
    if os.path.exists(manifest_path):
        with open(manifest_path, encoding="utf-8") as f:
            missing |= set(json.load(f)["clips"]) - set(refs)
    if missing:
        sys.exit(f"missing reference transcripts: {sorted(missing)}")
    report = render(*score(out, refs))
    with open(os.path.join(out, "report.md"), "w", encoding="utf-8") as f:
        f.write(report)
    print(report, end="")

if __name__ == "__main__":
    main()
