"""Fail-closed fixtures for the explicit GitHub auto-merge author allowlist."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from approved_author_auto_merge import parse_approved_authors


class ApprovedAuthorsTests(unittest.TestCase):
    def test_empty_allowlist_denies_everyone(self):
        self.assertEqual(parse_approved_authors(""), set())
        self.assertEqual(parse_approved_authors(" \n "), set())

    def test_author_list_supports_whitespace_commas_and_casefolding(self):
        self.assertEqual(
            parse_approved_authors("Shpalac, Agent-Bot\nother SHPALAC"),
            {"shpalac", "agent-bot", "other"},
        )

    def test_reject_invalid_logins_and_nonstring_inputs(self):
        for value in ("shpalac;other", "bad/login", "@someone", "-bad", None, 5):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    parse_approved_authors(value)


if __name__ == "__main__":
    unittest.main()
