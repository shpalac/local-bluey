"""Regression tests for GitHub-hosted-runner-only issue creation."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from issue_task_ci import ContractError
from runner_only_issue_contract import validate_runner_only_contract

VALID = """## Objective
Deliver a verifiable response.
## Acceptance criteria
- [ ] AC-1: Reject invalid request without side effects.
- [ ] AC-2: Return a stable result for a valid request.
## CI and validation
- GitHub-hosted runner: ubuntu-latest
- AC-1: tool/test_runner_only_issue_contract.py rejects invalid requests.
- AC-2: test/issues/issue_891_test.dart checks valid responses.
## Non-goals and runner limits
Physical devices and human approval are excluded, not accepted.
## Definition of done
Named tests pass at PR head and on main.
"""


class RunnerOnlyIssueTests(unittest.TestCase):
    def test_valid_runner_only_contract(self):
        self.assertIsNone(validate_runner_only_contract(VALID, 891))

    def test_non_runner_acceptance_is_rejected(self):
        for term in ("physical Mac", "real-device", "manual review",
                     "human approval", "hardware pairing", "TCC prompt"):
            bad = VALID.replace("Reject invalid request without side effects.",
                                f"Requires {term} before completion.")
            with self.subTest(term=term), self.assertRaisesRegex(ContractError, "non-runner"):
                validate_runner_only_contract(bad, 891)

    def test_runner_missing_or_unmapped_plan_rejected(self):
        for bad in (
            VALID.replace("- GitHub-hosted runner: ubuntu-latest", ""),
            VALID.replace("- AC-2: test/issues/issue_891_test.dart checks valid responses.", ""),
            VALID.replace("tool/test_runner_only_issue_contract.py rejects invalid requests.",
                          "manual inspection is required."),
        ):
            with self.subTest(bad=bad), self.assertRaises(ContractError):
                validate_runner_only_contract(bad, 891)

    def test_duplicate_nonconsecutive_or_placeholder_criteria_rejected(self):
        for bad in (
            VALID.replace("AC-2:", "AC-1:"),
            VALID.replace("AC-2:", "AC-3:"),
            VALID.replace("Return a stable result for a valid request.", "TBD"),
            VALID.replace("test/issues/issue_891_test.dart", "<test-file>"),
        ):
            with self.subTest(bad=bad), self.assertRaises(ContractError):
                validate_runner_only_contract(bad, 891)

    def test_runner_limits_documentation_can_exclude_real_devices(self):
        self.assertIsNone(validate_runner_only_contract(
            VALID.replace("Physical devices and human approval",
                          "Real iPhones, physical Macs and manual tests"), 891))


if __name__ == "__main__":
    unittest.main()
