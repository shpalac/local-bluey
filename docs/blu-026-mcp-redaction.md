# BLU-026: MCP output redaction boundary

The existing `SafetyGateRuntime` wraps per-call `McpToolSafetyGate`
approval. Untrusted MCP server descriptions are never instructions and an
unapproved tool cannot run.

Output map keys are normalized to reject common secret-field spellings:
tokens, passwords, passphrases, credentials, authorization headers, cookies,
API/access keys, session identifiers and private keys. Redaction is recursive
through nested map and list results, bounded by the existing resource limit.
Safe non-secret response fields retain their data. The caller receives only
a sanitized copy, not an authorization shortcut.

Run `flutter test test/mcp/safety_gate_secret_alias_test.dart` and the
existing `test/mcp/safety_gate_runtime_test.dart` regression suites.
This is keyword-based field redaction, not proof that arbitrary free-text
outputs cannot contain secrets; real-server transport containment and native
permissions require separate testing. No new egress path or persistence exists.

Rollback: revert the additional key aliases; existing approval remains
unchanged. The incomplete platform UI acceptance remains open.
