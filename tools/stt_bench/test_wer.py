"""Offline tests for the STT benchmark failure accounting (#270).

No model, microphone or private recording: a stub whisper CLI and tiny text
fixtures stand in for the real backends.
"""
import csv
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

import wer
from validate_inputs import validate

HERE = Path(__file__).parent


def fake_metrics(ref, hyp):
    wrong = sum(1 for r, h in zip(ref, hyp) if r != h)
    return wrong / len(ref), wrong / len(ref)


REFS = {"a.wav": "one two", "b.wav": "three four"}


def write_run(out, rows, transcripts):
    out = Path(out)
    with open(out / "timings.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["backend", "clip", "latency_ms", "peak_rss_bytes", "exit_status"])
        w.writerows(rows)
    for name, text in transcripts.items():
        (out / name).write_text(text, encoding="utf-8")


class ScoreTest(unittest.TestCase):
    def score(self, rows, transcripts, refs=REFS):
        with tempfile.TemporaryDirectory() as out:
            write_run(out, rows, transcripts)
            return wer.score(out, refs, metrics=fake_metrics)

    def test_two_successful_clips_are_complete(self):
        res, problems = self.score(
            [["good", "a.wav", 100, 5, 0], ["good", "b.wav", 300, 9, 0]],
            {"good--a.wav.txt": "one two", "good--b.wav.txt": "three four"})
        r = res[0]
        self.assertTrue(r["complete"])
        self.assertEqual((r["attempted"], r["succeeded"], r["failed"], r["scored"]), (2, 2, 0, 2))
        self.assertEqual(r["wer"], 0.0)
        self.assertEqual(problems, [])
        self.assertNotIn("INCOMPLETE", wer.render(res, problems))

    def test_success_plus_failure_without_output_is_incomplete(self):
        res, problems = self.score(
            [["flaky", "a.wav", 100, 5, 0], ["flaky", "b.wav", 10, 5, 3]],
            {"flaky--a.wav.txt": "one two"})
        r = res[0]
        self.assertFalse(r["complete"])
        self.assertEqual((r["attempted"], r["succeeded"], r["failed"]), (2, 1, 1))
        # Success latency excludes the quick failure; failure timing is separate.
        self.assertEqual((r["p50"], r["fail_p50"]), (100, 10))
        self.assertIn("flaky / b.wav: exit 3", problems[0])
        text = wer.render(res, problems)
        self.assertIn("INCOMPLETE - not comparable", text)
        self.assertIn("Caveat", text)

    def test_nonzero_exit_with_partial_output_is_not_scored(self):
        res, problems = self.score(
            [["p", "a.wav", 100, 5, 1]], {"p--a.wav.txt": "one"})
        r = res[0]
        self.assertEqual((r["succeeded"], r["failed"], r["scored"]), (0, 1, 0))
        self.assertIsNone(r["wer"])
        self.assertIn("partial output ignored", problems[0])

    def test_all_attempts_failed_still_shows_the_backend(self):
        res, _ = self.score(
            [["dead", "a.wav", 5, 0, 1], ["dead", "b.wav", 6, 0, 1]], {})
        self.assertEqual(len(res), 1)
        self.assertEqual((res[0]["succeeded"], res[0]["failed"]), (0, 2))
        self.assertIn("n/a", wer.render(res, []))

    def test_missing_transcript_with_exit_zero_is_a_failure(self):
        res, problems = self.score([["x", "a.wav", 1, 0, 0]], {})
        self.assertEqual(res[0]["failed"], 1)
        self.assertIn("no transcript written", problems[0])

    def test_success_without_reference_is_reported_not_scored(self):
        res, problems = self.score(
            [["g", "a.wav", 1, 0, 0], ["g", "c.wav", 1, 0, 0]],
            {"g--a.wav.txt": "one two", "g--c.wav.txt": "zzz"})
        self.assertEqual(res[0]["scored"], 1)
        self.assertFalse(res[0]["complete"])
        self.assertTrue(any("no reference" in p for p in problems))

    def test_incomplete_backend_is_flagged_next_to_a_complete_one(self):
        res, problems = self.score(
            [["a", "a.wav", 1, 0, 0], ["a", "b.wav", 1, 0, 0],
             ["b", "a.wav", 1, 0, 0], ["b", "b.wav", 1, 0, 2]],
            {"a--a.wav.txt": "one two", "a--b.wav.txt": "three four",
             "b--a.wav.txt": "one two"})
        by = {r["backend"]: r for r in res}
        self.assertTrue(by["a"]["complete"])
        self.assertFalse(by["b"]["complete"])

    def test_legacy_timings_without_exit_status_are_not_trusted(self):
        with tempfile.TemporaryDirectory() as out:
            Path(out, "timings.csv").write_text(
                "backend,clip,latency_ms,peak_rss_bytes\nold,a.wav,10,5\n")
            Path(out, "old--a.wav.txt").write_text("one two")
            res, problems = wer.score(out, REFS, metrics=fake_metrics)
        self.assertFalse(res[0]["complete"])
        self.assertIn("exit status unknown", problems[0])

    def test_empty_evaluation_set_and_missing_refs_fail_loudly(self):
        with tempfile.TemporaryDirectory() as out:
            with self.assertRaises(SystemExit) as e:
                wer.load_attempts(out)
            self.assertIn("nothing was attempted", str(e.exception))
            Path(out, "timings.csv").write_text(
                "backend,clip,latency_ms,peak_rss_bytes,exit_status\n")
            with self.assertRaises(SystemExit) as e:
                wer.load_attempts(out)
            self.assertIn("empty evaluation set", str(e.exception))
            with self.assertRaises(SystemExit):
                wer.load_refs(os.path.join(out, "nope.csv"))
            Path(out, "refs.csv").write_text("# only comments\n")
            with self.assertRaises(SystemExit):
                wer.load_refs(os.path.join(out, "refs.csv"))


    def test_equal_count_different_populations_are_not_comparable(self):
        res, problems = self.score(
            [["a", "a.wav", 1, 0, 0], ["b", "b.wav", 1, 0, 0]],
            {"a--a.wav.txt": "one two", "b--b.wav.txt": "three four"})
        self.assertTrue(all(not r["complete"] for r in res))
        self.assertIn("different clip identities", wer.render(res, problems))

    def test_manifest_reports_backend_with_no_attempts(self):
        import json
        with tempfile.TemporaryDirectory() as out:
            write_run(out, [["a", "a.wav", 1, 0, 0]], {"a--a.wav.txt": "one two"})
            Path(out, "expected.json").write_text(json.dumps(
                {"backends": ["a", "missing"], "clips": ["a.wav", "b.wav"]}))
            res, _ = wer.score(out, REFS, metrics=fake_metrics)
        self.assertEqual(len(res), 2)
        self.assertTrue(all(not r["complete"] for r in res))
        self.assertEqual(res[1]["attempted"], 0)

    def test_manifest_rejects_unselected_backend_population(self):
        import json
        with tempfile.TemporaryDirectory() as out:
            write_run(out, [["unexpected", "a.wav", 1, 0, 0]],
                      {"unexpected--a.wav.txt": "one two"})
            Path(out, "expected.json").write_text(json.dumps(
                {"backends": ["expected"], "clips": ["a.wav"]}))
            res, _ = wer.score(out, REFS, metrics=fake_metrics)
        self.assertTrue(all(not r["complete"] for r in res))

    def test_cli_rejects_missing_reference_before_metrics(self):
        with tempfile.TemporaryDirectory() as out:
            write_run(out, [["a", "missing.wav", 1, 0, 0]],
                      {"a--missing.wav.txt": "one two"})
            ref = Path(out, "refs.csv")
            ref.write_text("a.wav,one two\n")
            r = subprocess.run(["python3", str(HERE / "wer.py"), out, str(ref)],
                               capture_output=True, text=True, timeout=10)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("missing reference", r.stderr)
            self.assertFalse(Path(out, "report.md").exists())

    def test_duplicate_attempts_do_not_establish_completeness(self):
        res, _ = self.score(
            [["a", "a.wav", 1, 0, 0], ["a", "a.wav", 2, 0, 0]],
            {"a--a.wav.txt": "one two"})
        self.assertFalse(res[0]["complete"])


class InputTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fx = self.root / "fx"
        self.fx.mkdir()
        self.out = self.root / "out"
        (self.root / "models").mkdir()
        (self.root / "models/ggml-large-v3-turbo.bin").write_text("stub")
        (self.fx / "a.wav").write_text("stub audio")
        (self.fx / "refs.csv").write_text("a.wav,one two\n")

    def test_selection_records_exact_inputs(self):
        import json
        validate(self.root, self.fx, self.out, "whispercpp-turbo", "a.wav")
        manifest = json.loads((self.out / "expected.json").read_text())
        self.assertEqual(manifest["clips"], ["a.wav"])
        self.assertEqual(manifest["backends"], ["whispercpp-turbo"])

    def test_missing_selected_model(self):
        with self.assertRaisesRegex(SystemExit, "missing selected model"):
            validate(self.root, self.fx, self.out, "whispercpp-ivrit")

    def test_no_models(self):
        (self.root / "models/ggml-large-v3-turbo.bin").unlink()
        with self.assertRaisesRegex(SystemExit, "no selected models"):
            validate(self.root, self.fx, self.out)

    def test_no_audio(self):
        (self.fx / "a.wav").unlink()
        with self.assertRaisesRegex(SystemExit, "no selected audio"):
            validate(self.root, self.fx, self.out)

    def test_missing_selected_audio(self):
        with self.assertRaisesRegex(SystemExit, "missing selected audio"):
            validate(self.root, self.fx, self.out, clip_selection="missing.wav")

    def test_missing_reference(self):
        (self.fx / "refs.csv").write_text("other.wav,not selected\n")
        with self.assertRaisesRegex(SystemExit, "missing selected reference"):
            validate(self.root, self.fx, self.out)

    def test_duplicate_selection(self):
        with self.assertRaisesRegex(SystemExit, "duplicate selected backend"):
            validate(self.root, self.fx, self.out, "whispercpp-turbo whispercpp-turbo")


class RunnerTest(unittest.TestCase):
    def test_runner_rejects_absent_inputs_without_normal_wrote_output(self):
        for case in ("model", "audio", "reference"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as root:
                root = Path(root)
                (root / "models").mkdir()
                fx = root / "fx"
                fx.mkdir()
                if case != "model":
                    (root / "models/ggml-large-v3-turbo.bin").write_text("stub")
                if case != "audio":
                    (fx / "a.wav").write_text("stub")
                if case != "reference":
                    (fx / "refs.csv").write_text("a.wav,hello\n")
                r = subprocess.run(["sh", str(HERE / "run_bench.sh"), "--fixtures", str(fx)],
                                   env=dict(os.environ, STT_ROOT=str(root)),
                                   capture_output=True, text=True, timeout=10)
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn("Wrote", r.stdout)
                self.assertTrue(r.stderr)

    def test_runner_records_real_exit_status_with_a_stub_cli(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            cli = root / "whisper.cpp/build/bin/whisper-cli"
            cli.parent.mkdir(parents=True)
            cli.write_text(
                '#!/bin/sh\n'
                'while [ $# -gt 0 ]; do\n'
                '  case "$1" in -of) of="$2"; shift 2;; -f) f="$2"; shift 2;; *) shift;; esac\n'
                'done\n'
                'case "$f" in\n'
                '  *bad*) exit 3;;\n'
                '  *part*) echo partial > "$of.txt"; exit 1;;\n'
                '  *) echo ok > "$of.txt";;\n'
                'esac\n')
            cli.chmod(cli.stat().st_mode | stat.S_IEXEC)
            (root / "models").mkdir()
            (root / "models/ggml-large-v3-turbo.bin").write_text("stub")
            fx = root / "fx"
            fx.mkdir()
            for n in ("good.wav", "bad.wav", "part.wav"):
                (fx / n).write_text("x")
            (fx / "refs.csv").write_text("good.wav,ok\nbad.wav,x\npart.wav,y\n")
            env = dict(os.environ, STT_ROOT=str(root), STT_TIME="env")
            r = subprocess.run(
                ["sh", str(HERE / "run_bench.sh"), "--fixtures", str(fx)],
                env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stderr)
            run_dir = next((root / "results").iterdir())
            with open(run_dir / "timings.csv", newline="") as f:
                rows = {r["clip"]: r for r in csv.DictReader(f)}
            self.assertEqual(rows["good.wav"]["exit_status"], "0")
            self.assertEqual(rows["bad.wav"]["exit_status"], "3")
            self.assertEqual(rows["part.wav"]["exit_status"], "1")
            refs = {"good.wav": "ok", "bad.wav": "x", "part.wav": "y"}
            res, problems = wer.score(str(run_dir), refs, metrics=fake_metrics)
            self.assertEqual((res[0]["attempted"], res[0]["succeeded"], res[0]["failed"]), (3, 1, 2))
            self.assertFalse(res[0]["complete"])


if __name__ == "__main__":
    unittest.main()
