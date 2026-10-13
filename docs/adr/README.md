# Architecture decision records

Architecture decisions live here, not in issue comments or agent memory. A decision is a reviewable contract, **not** evidence that the feature shipped. Start with [ADR-001](ADR-001-bluey-delivery-decisions.md) (accepted *for implementation planning*) and [ADR-002](002-observation-privacy.md) (proposed and **not** ratified).

## Decision register

| ADR | Lifecycle | Scope | Implemented boundary / open work |
| --- | --- | --- | --- |
| [ADR-001](ADR-001-bluey-delivery-decisions.md) | Accepted for planning only | Consent, SafetyGate, storage, workflow, network and platform defaults | [observation policy](../../lib/services/observation_policy.dart), [SafetyGate](../../lib/services/safety_gate.dart), [support matrix](../../lib/services/support_matrix.dart), [workflow DSL](../../lib/workflows/workflow_dsl.dart); remaining implementation tracked by linked BLU issues |
| [ADR-002](002-observation-privacy.md) | Proposed, not ratified | Consent lifecycle, frames, sensitivity and retention | [policy tests](../../test/observation_policy_test.dart) cover a pure contract; native screen exclusion, storage and real-device acceptance remain open |

The machine-checkable [decision-to-code map](traceability.json) traces **every numbered decision** to an existing implementation boundary, a regression test and an outstanding issue. Its `coverage` field is either `contract` (a relevant existing boundary is tested, but **not** necessarily a complete feature) or `planned` (the decision is **not** implemented end to end). Neither value is product approval. Use [BLU-080](https://github.com/shpalac/local-bluey/issues/638) for system-wide release traceability.

## Authoring and approval

1. Copy [ADR-TEMPLATE.md](ADR-TEMPLATE.md). Give the file an immutable ID, summarize the problem and alternatives, and identify the decision authority. Begin as **Proposed**. An agent may record a proposal but cannot silently approve it.
2. Include explicit inputs and validation, denied/unknown permissions, offline and cancellation behavior, secrets/egress boundaries, supported platforms, migrations, rollback, tests and unresolved dependencies. Never embed user data, tokens, screen captures or live operational logs.
3. Record the actual approving authority and review evidence **before** changing status to Accepted. `ADR-001` is accepted for *planning*, not a certification of implementation. `ADR-002` remains proposed pending ratification.
4. Add or update `traceability.json`: link each numbered decision to a *real tracked* code boundary, a deterministic test and an issue. Use `planned` where behavior is missing; do not relabel test stubs as end-to-end evidence. Update [acceptance map](../ACCEPTANCE_MAP.md) and reference the issue in the PR.
5. Supersede a decision with a new ADR and cross-links; do not erase prior reasoning. Preserve default-off observation and human SafetyGate approval during migration or rollback.

## Verification

```sh
flutter pub get --enforce-lockfile
flutter test test/issues/issue_634_test.dart
flutter analyze
```

The focused test checks registry coverage, exact linked paths, lifecycle statements, invalid IDs and traversal references; CI runs it through the issue-specific temporary acceptance manifest. No new runtime feature, network egress, permission or storage behavior is introduced. To roll back, revert the docs/registry/test PR; pre-existing ADRs and runtime behavior remain unchanged. Human sign-off of future decisions and hardware/native verification remain independent gates.
