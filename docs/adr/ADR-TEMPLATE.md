# ADR-XXX: Short decision title

**Status:** Proposed (not approved). **Date:** YYYY-MM-DD.
**Decision authority:** Unassigned until a reviewer accepts the decision.
**Issue:** Link the owning BLU issue and dependencies.
**Scope:** Describe which feature/platform this proposal would affect.

## Context and ground truth

Name the current production code paths, call sites, existing tests, support
matrix and risk. Distinguish present behavior from proposed behavior.

## Decision

1. Describe a single specific, reviewable decision, including its typed
   inputs/outputs, validation and explicit error states.
2. State deny-by-default behavior for unknown/malformed input, missing
   consent, expired/revoked permissions, offline operation and cancellation.

## Alternatives and trade-offs

Describe considered options and why each was accepted or rejected, including
privacy, performance, compatibility and maintenance costs.

## Security and privacy

State where data/keys live, retention and deletion behavior, permitted network
egress, log/artifact redaction and SafetyGate approval boundaries. Never claim
that local tests certify physical OS permissions or device behavior.

## Rollout, migration and rollback

List flags/default-off behavior, schema migrations, downgrade failures,
monitoring and a rollback plan that preserves existing Routines and safety
barriers. Identify manual/native acceptance gates.

## Decision-to-implementation evidence

| Decision number | Current code boundary | Test case | Follow-up issue | Coverage (contract / planned) |
| --- | --- | --- | --- | --- |
| 1 | `lib/...` | `test/...` | #123 | planned |

Add every numbered decision to `docs/adr/traceability.json`. A `contract`
link only proves a relevant tested boundary, not that the full feature shipped.

## Approval record

**Decision authority:** Pending. **Review link:** Pending.
**Effective date:** Not applicable until accepted.
Do not self-ratify or remove human approval requirements.
