# BLU-033 Home Assistant single-dispatch boundary

`McpToolSafetyGate.authorize` validates the existing per-call server
allowlist, tool schema, arguments and human permission but intentionally
does not invoke the MCP tool. The existing `execute` API remains available
and continues to authorize *then* invoke once.

`HomeAssistantAdapter` uses the authorization-only path before checking
entity approval and a local transport. This prevents dry-run requests from
performing an MCP call and prevents a live request from dispatching both an
MCP action and a Home Assistant transport action. A live call still needs
explicit permission, local/online status and entity approval.

Run `flutter test test/mcp/home_assistant_single_dispatch_test.dart` and
`flutter test test/mcp/home_assistant_adapter_test.dart` plus gate tests.
This contract does not perform a real Home Assistant network operation;
native UX, privacy/egress and reversible physical device scenarios remain
manual gaps. Rollback reverts the isolated authorize-only route, with no
persistent data migrations.
