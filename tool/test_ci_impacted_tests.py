"""Offline tests for concurrent impacted-suite selection and safety."""
import json
from pathlib import Path
import tempfile
import unittest

from ci_impacted_tests import select_files, main


class ImpactedFilesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "test" / "workflows").mkdir(parents=True)
        for file in ("test/a_test.dart", "test/workflows/b_test.dart"):
            (self.root / file).write_text("void main() {}\\n", encoding="utf-8")

    def test_selected_suite_sorted_once(self):
        selected = select_files(json.dumps([
            "test/workflows/b_test.dart", "test/a_test.dart"
        ]), self.root)
        self.assertEqual(selected, ["test/a_test.dart", "test/workflows/b_test.dart"])

    def test_invalid_or_empty_selection_fails_closed(self):
        for value in ('', 'not json', '{}', '[]', 'null', '42', '["test/no_test.dart"]',
                      '["test/a_test.dart", "test/a_test.dart"]',
                      '["../test/a_test.dart"]', '["test/x\\ny_test.dart"]',
                      '["test/workflows/../../a_test.dart"]', '["/tmp/x_test.dart"]'):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    select_files(value, self.root)

    def test_symlink_escape_is_denied(self):
        outside = self.root / "outside_test.dart"
        outside.write_text("void main() {}\\n", encoding="utf-8")
        (self.root / "test" / "escape_test.dart").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "escapes test root"):
            select_files('["test/escape_test.dart"]', self.root)

    def test_main_writes_safe_newline_delimited_files(self):
        output = self.root / "selected.txt"
        result = main(["--root", str(self.root), "--output", str(output),
                       "--test-files", '["test/workflows/b_test.dart","test/a_test.dart"]'])
        self.assertEqual(result, 0)
        self.assertEqual(output.read_text(), "test/a_test.dart\\ntest/workflows/b_test.dart\\n")

    def test_main_never_outputs_success_on_missing_suite(self):
        output = self.root / "selected.txt"
        rc = main(["--root", str(self.root), "--output", str(output),
                   "--test-files", "[]"])
        self.assertEqual(rc, 1)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
