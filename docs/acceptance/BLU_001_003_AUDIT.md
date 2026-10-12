# BLU-001 through BLU-003: acceptance CI audit

Audit date: 2026-10-12. Scope: current `main` behavior and issue contracts
[#554](https://github.com/shpalac/local-bluey/issues/554),
[#555](https://github.com/shpalac/local-bluey/issues/555), and
[#556](https://github.com/shpalac/local-bluey/issues/556).

## Findings

All three already had named Flutter acceptance tests in the shared
`docs/acceptance/criteria.json`, run by `acceptance-evidence`. That shared
manifest did **not** mirror all four numbered issue criteria or make issue
completeness obvious. This PR moves them into individual checked manifests
and runs their combined tests once, retaining the existing fail-closed
evidence semantics. It adds **no claim that native capture is verified**.

| Issue | AC | Evidence and boundary |
| --- | --- | --- |
| BLU-001 #554 | AC-1 | Consent/restart/sensitive-window contracts automated; **signed review and real Mac check remain manual** |
| BLU-001 #554 | AC-2 | Safe, denied permission, cancelled, expired and no-allowlist session tests in deterministic fake service |
| BLU-001 #554 | AC-3 | No-vision and excluded-surface fixture tests automated; **actual native egress/privacy requires hardware and reviewer** |
| BLU-001 #554 | AC-4 | Existing `static`, `test` and `acceptance-evidence` lanes; **PR-head evidence link and review remain manual** |
| BLU-002 #555 | AC-1 | Canonical DTO round-trip, version, enum, ID, timestamp and confidence tests |
| BLU-002 #555 | AC-2 | Valid/invalid pure DTO test paths (no network, timeout, OS permission or restart state in DTO) |
| BLU-002 #555 | AC-3 | Strict whitelist of fields and no capture/IO side effects; no claim about hypothetical future storage integration |
| BLU-002 #555 | AC-4 | Existing static/test CI plus reviewer evidence still required |
| BLU-003 #556 | AC-1 | Hebrew/English corpus, sensitive metadata and secret-free verdict fixtures |
| BLU-003 #556 | AC-2 | Lock/private/unknown and blank OCR denial, stop races, background focus refusal |
| BLU-003 #556 | AC-3 | Production proactive vision OFF and modeled no-egress; **atomic native pixel crop is not implemented/verified** |
| BLU-003 #556 | AC-4 | Existing static/test CI plus reviewer evidence still required |

#556 is **closed** in GitHub, but its test manifest intentionally retains
`not_implemented` native crop verification and `manual_required` real
permission/focus/privacy review. This PR does not reopen it, approve screen
capture, or retroactively certify those requirements.

## CI execution

`acceptance-evidence` now has two non-overlapping manifest groups:

- `tool/blu_001_003_acceptance.py --run-tests` validates the four AC IDs for
  each of the three issues, preserves native/manual/implementation gaps,
  executes every unique named referenced test and reports sanitized status.
- `tool/acceptance_criteria.py --run-tests` continues to validate #558,
  #563 and #608. Those entries remain as originally scoped.

`tool/test_blu_001_003_acceptance.py` ensures that missing AC entries,
missing tests, or attempts to relabel unresolved hardware criteria are
failures. Failure, timeout, skipping or missing JSON test events are already
rejected by the existing `tool/acceptance_criteria.py` executor.

## Completion limitation

These tests run on a GitHub-hosted runner without granting a real user's
macOS Accessibility/Screen Recording/TCC permissions. A green CI run cannot
prove pixel isolation, secrets absent from physical screen capture,
approval of a privacy threat model or sign-off on a schema migration.
Those criteria remain reported as **manual_required** or
**not_implemented** until real implementation and independent evidence exist.

No per-issue GitHub Actions workflow needs to be left permanently enabled
once an issue is closed; the manifests and regression suites act as stable
documentation and reusable coverage unless deliberately replaced with
equivalent feature integration tests.
