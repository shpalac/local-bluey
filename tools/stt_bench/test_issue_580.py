"""Offline issue #580 acceptance fixtures for the production STT scorer."""
import csv
import tempfile
import unittest
from pathlib import Path

import wer


def metrics(references, hypotheses):
    return (0.0, 0.0) if references == hypotheses else (1.0, 1.0)


def fixture(directory, transcript):
    root = Path(directory)
    with (root / "timings.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["backend", "clip", "latency_ms", "peak_rss_bytes", "exit_status"])
        writer.writerow(["offline", "hebrew.wav", "20", "1024", "0"])
    (root / "offline--hebrew.wav.txt").write_text(transcript, encoding="utf-8")


class BaselineReproducibility(unittest.TestCase):
    def test_hebrew_nikud_and_punctuation_baseline_reproducible(self):
        reference = {"hebrew.wav": "שָׁלוֹם, עולם!"}
        with tempfile.TemporaryDirectory() as directory:
            fixture(directory, "שלום עולם")
            first = wer.score(directory, reference, metrics=metrics)
            second = wer.score(directory, reference, metrics=metrics)
            self.assertEqual(first, second)
            self.assertEqual(first[0][0]["wer"], 0.0)
            self.assertEqual(first[0][0]["cer"], 0.0)
            self.assertTrue(first[0][0]["complete"])


class InvalidOutputFailClosed(unittest.TestCase):
    def test_empty_success_transcript_is_incomplete(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture(directory, "  \n  ")
            results, problems = wer.score(
                directory, {"hebrew.wav": "שלום עולם"}, metrics=metrics)
            self.assertFalse(results[0]["complete"])
            self.assertEqual(results[0]["scored"], 0)
            self.assertEqual(results[0]["failed"], 1)
            self.assertIsNone(results[0]["wer"])
            self.assertTrue(any("empty transcript" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
