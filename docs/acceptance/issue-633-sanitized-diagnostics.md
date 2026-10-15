# Issue #633: sanitized diagnostics report slice

The existing `Diagnostics.buildReport` caller is the production text-copy seam. It emits only fixed headers and check IDs/statuses. Platform and role now require short ASCII identifiers; invalid, multiline or long values become `unknown`. The report does not collect screenshots, audio, check titles or fix details. No new I/O or network egress is introduced.

Security limit: arbitrary check IDs are still emitted from `CheckResult.id` and the generic regular-expression key redaction cannot guarantee all tokens or PII are absent. This is **not** a complete opt-in debug-bundle implementation. Do not treat it as a security-reviewed attachment export.

Run `flutter test test/issue_633_sanitized_diagnostics_test.dart` and `flutter test test/diagnostics_test.dart`. A maintainer must review native share/copy destinations, explicit consent, cancellation, size bounds and true device permissions before full acceptance.

Rollback: revert the PR. There is no persistent migration.
