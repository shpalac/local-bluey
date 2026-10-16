# BLU-021 Synthetic benchmark harness gap analysis

## Scope

Refs #577 only.

## Automated acceptance coverage

- AC-1: deterministic precision, recall, F1 and fake-time metrics are covered by synthetic benchmark tests.
- AC-2: synthetic success/failure traces, validation and restart paths are covered by synthetic trace harness tests.
- AC-3: invalid traces are rejected without storing or transmitting data.
- AC-4: the benchmark module remains test-only and has no user-facing surface.

## Remaining gap

Real BLU-006/BLU-008 production capture integration requires runtime validation against the real capture pipeline, privacy controls, and device permissions.

The in-repo follow-up wires only deterministic adapters around existing pure Dart components. Hardware/TCC validation remains a manual validation step.

## Bounded synthetic trace collection (Refs #577)

`SyntheticTraceHarness` now defaults to a 10,000-event in-memory cap.
Callers may configure a positive cap no larger than 100,000. Once full,
`record` rejects new samples before changing stored ids, traces or
calculated metrics. This protects deterministic stress tests from
accidentally accumulating an unbounded number of synthetic observations.

Run `flutter test test/benchmark/synthetic_trace_capacity_test.dart`.
The limit adds no telemetry, persistent state, device capture or permission
requirements. Native privacy and real BLU-006/008 integration remain open.
