"""Offline Hebrew regression matrix: no model, audio, cloud or permissions."""
import tempfile
import unittest
from pathlib import Path

from hebrew_baseline import error_counts, load_csv, normalize, summarize


def attempt(backend, clip, hypothesis, latency=100, state="success"):
    return {
        "backend": backend, "clip": clip, "reference": "פתח את הדפדפן",
        "hypothesis": hypothesis, "latency_ms": latency, "state": state,
    }


class HebrewBaselineTest(unittest.TestCase):
    def test_reproducible_success_and_comparison(self):
        rows = [
            attempt("local-a", "one", "פתח את הדפדפן", 100),
            attempt("local-a", "two", "פתח את הדפדפן", 200),
            attempt("local-b", "one", "פתח את דפדפן", 120),
            attempt("local-b", "two", "פתח את דפדפן", 220),
        ]
        first = summarize(rows)
        self.assertEqual(first, summarize(list(reversed(rows))))
        self.assertEqual(first["local-a"]["wer"], 0)
        self.assertEqual(first["local-a"]["cer"], 0)
        self.assertEqual(first["local-a"]["p50_latency_ms"], 150)
        self.assertGreater(first["local-b"]["wer"], first["local-a"]["wer"])
        self.assertTrue(all(item["complete"] for item in first.values()))

    def test_hebrew_normalization_and_code_switch(self):
        self.assertEqual(normalize("שָׁלוֹם,  WhatsApp!"), "שלום whatsapp")
        self.assertEqual(error_counts("שָׁלוֹם", "שלום")["word_errors"], 0)
        self.assertEqual(error_counts("שלום", "שולם")["character_errors"], 2)

    def test_empty_reference_is_not_claimed_accurate(self):
        result = summarize([{**attempt("local", "silence", ""), "reference": ""}])
        self.assertIsNone(result["local"]["wer"])
        self.assertIsNone(result["local"]["cer"])

    def test_invalid_input_and_duplicate(self):
        with self.assertRaisesRegex(ValueError, "empty"):
            summarize([])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            summarize([attempt("a", "x", "a"), attempt("a", "x", "b")])
        with self.assertRaisesRegex(ValueError, "latency"):
            summarize([attempt("a", "x", "ok", -1)])
        with self.assertRaisesRegex(ValueError, "state"):
            summarize([attempt("a", "x", "", state="unknown")])

    def test_offline_timeout_permission_cancel_restart_fail_closed(self):
        for state in ("offline", "timeout", "permission_denied",
                      "cancelled", "restart", "invalid_input"):
            with self.subTest(state=state):
                rows = [
                    attempt("healthy", "x", "פתח את הדפדפן"),
                    attempt("fault", "x", None, None, state),
                ]
                result = summarize(rows)
                self.assertTrue(result["healthy"]["complete"])
                self.assertFalse(result["fault"]["complete"])
                self.assertIsNone(result["fault"]["wer"])
                self.assertEqual(result["fault"]["failures"], {state: 1})

    def test_population_mismatch_disables_ranking(self):
        rows = [
            attempt("a", "one", "פתח את הדפדפן"),
            attempt("b", "two", "פתח את הדפדפן"),
        ]
        self.assertTrue(all(not row["complete"]
                            for row in summarize(rows).values()))

    def test_csv_roundtrip_text_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "cases.csv"
            source.write_text(
                "backend,clip,state,reference,hypothesis,latency_ms\n"
                "local,one,success,פתח את הדפדפן,פתח את הדפדפן,42\n",
                encoding="utf-8")
            self.assertEqual(summarize(load_csv(source))["local"]["wer"], 0)


if __name__ == "__main__":
    unittest.main()
