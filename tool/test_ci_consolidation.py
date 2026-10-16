"""Guard legacy CI check names while moving duplicated work into central CI."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent


class ConsolidatedCiTest(unittest.TestCase):
    def read_workflow(self, name):
        return (ROOT / ".github" / "workflows" / name).read_text(encoding="utf-8")

    def test_legacy_fast_ci_does_not_duplicate_flutter(self):
        workflow = self.read_workflow("pr-fast-ci.yml")
        self.assertIn("name: Fast CI (format analyze test)", workflow)
        self.assertIn("pull_request:", workflow)
        self.assertNotIn("flutter test", workflow)
        self.assertNotIn("flutter analyze", workflow)
        self.assertIn("test_ci_gate.py", workflow)

    def test_native_lane_retains_xctest_without_prebuilding_mac(self):
        workflow = self.read_workflow("macos-native-build-lane.yml")
        self.assertIn("xcodebuild test", workflow)
        self.assertIn("flutter build macos --config-only", workflow)
        self.assertNotIn("flutter build macos --debug", workflow)
        self.assertNotIn("- run: flutter test", workflow)

    def test_ios_feasibility_has_a_fail_closed_detection_gate(self):
        workflow = self.read_workflow("temp-issue-596.yml")
        self.assertIn("PR_BASE_SHA:", workflow)
        self.assertIn("git diff --name-only", workflow)
        self.assertIn("needs: detect", workflow)
        self.assertIn("needs.detect.outputs.relevant == 'true'", workflow)

    def test_central_gate_remains_required(self):
        workflow = self.read_workflow("ci.yml")
        self.assertIn("run: python3 tool/ci_gate.py", workflow)
        self.assertIn("test_ci_consolidation.py", workflow)
        self.assertIn("needs.detect.outputs.full_tests", workflow)


if __name__ == "__main__":
    unittest.main()
