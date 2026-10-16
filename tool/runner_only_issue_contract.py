"""Validate newly opened issues as exclusively GitHub-hosted runner tasks.

No claim that a named test exists is made here: the PR acceptance gate
independently validates actual executable evidence on the PR head.
"""
import re

from issue_task_ci import ContractError, validate_issue_body

SECTION = re.compile(r"(?ims)^##[ \t]+([^\n]+)\n([\s\S]*?)(?=^##[ \t]+|\Z)")
AC = re.compile(r"(?im)^[ \t]*-[ \t]*\[[ xX]\][ \t]*AC-([1-9]\d*):[ \t]*(.+)$")
PLAN = re.compile(r"(?im)^[ \t]*-[ \t]*AC-([1-9]\d*):[ \t]*(.+)$")
HOSTED = re.compile(r"(?i)\b(?:ubuntu|macos|windows)-(?:latest|\d{2}(?:\.\d{2})?)\b")
TEST = re.compile(r"(?i)(?:\btest/|\btool/|\bintegration_test/|\bflutter test\b|\bpython3? -m unittest\b)")
NOT_RUNNABLE = re.compile(
    r"(?i)\b(?:manual(?:ly)?|physical(?:ly)?|real[ -]device|"
    r"device[ -]only|human (?:sign[ -]?off|approval)|actual (?:mac|iphone|ipad)|"
    r"hardware pairing|tcc (?:prompt|consent|session))\b"
)
PLACEHOLDER = re.compile(r"(?i)(?:<[^>]+>|\bTBD\b|\bTODO\b)")


def validate_runner_only_contract(body: str, issue_number: int) -> None:
    """Validate scope and one concrete hosted-CI test plan per numbered AC."""
    ids = validate_issue_body(body, issue_number)
    sections = {title.strip().lower(): value for title, value in SECTION.findall(body)}
    for title in ("objective", "acceptance criteria", "ci and validation",
                  "non-goals and runner limits", "definition of done"):
        if not sections.get(title, "").strip():
            raise ContractError(f"#{issue_number}: missing ## {title} section")

    criteria = AC.findall(sections["acceptance criteria"])
    numbers = [int(number) for number, _ in criteria]
    if numbers != list(range(1, len(numbers) + 1)) or len(ids) != len(criteria):
        raise ContractError(f"#{issue_number}: require sequential AC-1, AC-2, ...")
    for number, requirement in criteria:
        if NOT_RUNNABLE.search(requirement):
            raise ContractError(f"#{issue_number}: AC-{number} requires non-runner verification")
        if PLACEHOLDER.search(requirement):
            raise ContractError(f"#{issue_number}: AC-{number} contains a placeholder")

    validation = sections["ci and validation"]
    if not re.search(r"(?im)^[ \t]*-[ \t]*GitHub-hosted runner:[ \t]*\S", validation):
        raise ContractError(f"#{issue_number}: name a GitHub-hosted runner")
    if not HOSTED.search(validation):
        raise ContractError(f"#{issue_number}: use an ubuntu/macos/windows hosted runner")
    checks = PLAN.findall(validation)
    if [int(number) for number, _ in checks] != numbers:
        raise ContractError(f"#{issue_number}: map exactly one runner test plan per AC")
    for number, check in checks:
        if NOT_RUNNABLE.search(check) or not TEST.search(check) or PLACEHOLDER.search(check):
            raise ContractError(f"#{issue_number}: AC-{number} needs an executable runner test plan")
