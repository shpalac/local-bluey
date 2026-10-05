#!/usr/bin/env python3
"""Score benchmark runs: normalized Hebrew WER/CER + latency stats (#195).

Usage: wer.py RESULTS_DIR [refs.csv]
refs.csv rows: filename,transcript  (filename without directory)
Requires: pip install jiwer
"""
import csv, glob, os, re, sys, unicodedata

def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).lower()
    # strip nikud, punctuation, collapse whitespace
    s = re.sub(r"[\u0591-\u05C7]", "", s)
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    return " ".join(s.split())

def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out, refs_path = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
    if refs_path is None:
        cand = sorted(glob.glob(os.path.join(os.path.dirname(out), "*", "refs.csv")))
        refs_path = cand[-1] if cand else "refs.csv"
    refs = {}
    if os.path.exists(refs_path):
        with open(refs_path, newline="", encoding="utf-8") as f:
            for row in csv.reader(f):
                if row and not row[0].startswith("#"):
                    refs[row[0].strip()] = row[1].strip()
    else:
        sys.exit(f"refs.csv not found at {refs_path}")
    try:
        import jiwer
    except ImportError:
        sys.exit("pip install jiwer")
    rows, timings = [], {}
    tfile = os.path.join(out, "timings.csv")
    if os.path.exists(tfile):
        with open(tfile, newline="") as f:
            for r in csv.DictReader(f):
                timings.setdefault(r["backend"], []).append(
                    (int(r["latency_ms"]), int(r["peak_rss_bytes"])))
    hyps = glob.glob(os.path.join(out, "*--*.txt"))
    by_backend = {}
    for h in hyps:
        name = os.path.basename(h)[:-4]
        backend, clip = name.split("--", 1)
        if clip not in refs:
            continue
        with open(h, encoding="utf-8") as f:
            hyp = f.read()
        by_backend.setdefault(backend, []).append((refs[clip], hyp))
    for backend, pairs in sorted(by_backend.items()):
        ref = [normalize(r) for r, _ in pairs]
        hyp = [normalize(h) for _, h in pairs]
        wer = jiwer.wer(ref, hyp)
        cer = jiwer.cer(ref, hyp)
        ts = timings.get(backend, [])
        lats = sorted(t for t, _ in ts)
        p50 = lats[len(lats) // 2] if lats else 0
        p95 = lats[int(len(lats) * 0.95)] if lats else 0
        peak = max((m for _, m in ts), default=0)
        rows.append((backend, len(pairs), wer, cer, p50, p95, peak // 1048576))
    lines = ["| Backend | Clips | WER | CER | p50 ms | p95 ms | Peak RSS MB |",
             "|---|---|---|---|---|---|---|"]
    for b, n, w, c, p50, p95, peak in rows:
        lines.append(f"| {b} | {n} | {w:.3f} | {c:.3f} | {p50} | {p95} | {peak} |")
    with open(os.path.join(out, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))

if __name__ == "__main__":
    main()
