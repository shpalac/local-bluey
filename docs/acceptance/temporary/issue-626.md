# Issue 626: local data deletion failure containment

The existing Settings > Data and privacy controls call the registered store clear functions and DataRegistry.deleteAll. This bounded change prevents raw exception messages from appearing in debug logs or deletion snackbars, without suppressing explicit error reporting or changing the ordering and semantics of deletion.

Run: `flutter test test/local_data_control_center_failure_test.dart test/data_registry_test.dart`.

The new tests cover a registered failure's stable identifier and absence of exception secrets in debug output. They do not establish full absence of PII in unrelated files, exports or artifacts, nor verify disk deletion for every store. A native macOS run, platform-specific Routines compatibility, storage sizes, export, and independent deletion verification remain gaps. No network calls or additional persistence are introduced.

Rollback: revert the generic failure-message changes and the added tests/manifest evidence. Do not remove existing registry stores or deletion logic.
