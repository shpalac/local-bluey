"""Regression tests for CI impact routing and conservative fallbacks."""
import json
from pathlib import Path
import tempfile
import unittest

from ci_impact import impacted_tests, plan


class ImpactPlanningTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "lib/workflows").mkdir(parents=True)
        (self.root / "test").mkdir()
        (self.root / "lib/workflows/workflow_dsl.dart").write_text(
            "class WorkflowDls {}\n", encoding="utf-8"
        )
        (self.root / "lib/workflows/workflow_execution.dart").write_text(
            "import 'workflow_dsl.dart';\n", encoding="utf-8"
        )
        (self.root / "test/workflow_dsl_test.dart").write_text(
            "import 'package:local_bluey/workflows/workflow_dsl.dart';\n",
            encoding="utf-8",
        )
        (self.root / "test/workflow_execution_test.dart").write_text(
            "import 'package:local_bluey/workflows/workflow_execution.dart';\n",
            encoding="utf-8",
        )
        (self.root / "test/unrelated_test.dart").write_text(
            "void main() {}\n", encoding="utf-8"
        )

    def test_docs_only_skips_flutter_lanes(self):
        result = plan(["docs/INCIDENT_RUNBOOK.md", "README.md"], "pull_request", self.root)
        self.assertFalse(result["full_ci"])
        self.assertFalse(any(result["lanes"].values()))

    def test_acceptance_manifest_requires_acceptance(self):
        result = plan(["docs/acceptance/temporary/issue-637.json"], "pull_request", self.root)
        self.assertTrue(result["lanes"]["acceptance"])
        self.assertFalse(result["lanes"]["test"])
        self.assertFalse(result["lanes"]["build_ios"])

    def test_test_only_selects_changed_test(self):
        result = plan(["test/workflow_dsl_test.dart"], "pull_request", self.root)
        self.assertEqual(result["test_files"], ["test/workflow_dsl_test.dart"])
        self.assertFalse(result["full_tests"])
        self.assertTrue(result["lanes"]["test"])

    def test_workflow_dependency_reverse_graph_selects_downstream_tests(self):
        result = plan(["lib/workflows/workflow_dsl.dart"], "pull_request", self.root)
        self.assertEqual(result["test_files"], [
            "test/workflow_dsl_test.dart", "test/workflow_execution_test.dart",
        ])
        self.assertTrue(result["lanes"]["docs"])
        self.assertFalse(result["lanes"]["simulator"])

    def test_missing_source_mapping_runs_all_flutter_tests(self):
        (self.root / "lib/workflows/new_file.dart").write_text("class New {}\n")
        result = plan(["lib/workflows/new_file.dart"], "pull_request", self.root)
        self.assertTrue(result["full_tests"])
        self.assertFalse(result["full_ci"])

    def test_edited_test_fixture_runs_all_flutter_tests(self):
        result = plan(["test/fixtures/golden.png"], "pull_request", self.root)
        self.assertTrue(result["full_tests"])

    def test_missing_changed_test_runs_all_flutter_tests(self):
        result = plan(["test/deleted_test.dart"], "pull_request", self.root)
        self.assertTrue(result["full_tests"])

    def test_android_only_selects_android_native_and_single_api(self):
        result = plan(["android/app/src/main/MainActivity.kt"], "pull_request", self.root)
        self.assertTrue(result["lanes"]["android_integration"])
        self.assertFalse(result["lanes"]["build_ios"])
        self.assertEqual(result["android_matrix"], [34])

    def test_unknown_root_or_shared_library_requires_full(self):
        for path in ["lib/main.dart", "assets/app.png", ".github/workflows/ci.yml"]:
            with self.subTest(path=path):
                result = plan([path], "pull_request", self.root)
                self.assertTrue(result["full_ci"])
                self.assertTrue(all(result["lanes"].values()))

    def test_non_pr_and_empty_changes_require_full(self):
        for event, paths in [("push", []), ("merge_group", ["README.md"]),
                             ("pull_request", [])]:
            with self.subTest(event=event):
                self.assertTrue(plan(paths, event, self.root)["full_ci"])

    def test_plan_json_is_serializable(self):
        result = plan(["README.md"], "pull_request", self.root)
        self.assertEqual(json.loads(json.dumps(result))["android_matrix"], [34])

    def test_reject_unsafe_paths(self):
        for path in ["../README.md", "/tmp/foo.md", "docs/evil\nname.md"]:
            with self.subTest(path=path):
                self.assertTrue(plan([path], "pull_request", self.root)["full_ci"])


if __name__ == "__main__":
    unittest.main()
