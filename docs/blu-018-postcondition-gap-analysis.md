# BLU-018 Postcondition verification engine gap analysis

## Current state

PR #734 delivered the pure Dart verification engine, deterministic fake-host coverage, temporary acceptance CI, acceptance manifest entries, and rollback documentation.

## Acceptance status

- AC-1 satisfied by deterministic verifier tests: unchanged UI evidence does not confirm success and timeout remains inconclusive.
- AC-2 satisfied for the implemented pure Dart slice: happy path, malformed input, timeout/cancellation, denial, offline evidence, and restart-empty behavior are covered by deterministic tests.
- AC-3 satisfied for the implemented slice: no network execution, secret retention, or exception leakage.
- AC-4 satisfied for the implemented slice: focused validation commands are documented.

## Remaining scope

The remaining gap is integration, not verifier logic:

1. Wire production SafetyGate and HostControl observation readers.
2. Add real macOS/TCC permission validation as manual acceptance.
3. Add persisted restart recovery integration where product storage policy permits it.
4. Replace temporary acceptance CI only after the above integrations exist.

## Implementation plan

Keep the existing fail-closed contract. Add adapters behind existing interfaces, with explicit consent, local-only observation, no raw secret capture, and deterministic integration fixtures.
