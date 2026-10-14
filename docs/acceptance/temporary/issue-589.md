# BLU-033 adapter verification and risks

The opt-in Home Assistant adapter is a fake-backed, network-free boundary.
It uses `McpToolSafetyGate.execute` and then an explicit entity/service approval
for **every** operation, including locks. Unknown entities are refused, and
dry-run is the default. A caller must enable the feature and provide its own
local-endpoint policy, online probe and transport. The module never persists
tokens, entities or permissions.

Run: `dart format --output=none --set-exit-if-changed lib/mcp test/mcp`,
`flutter analyze lib/mcp test/mcp`,
`flutter test test/mcp/home_assistant_adapter_test.dart`,
`flutter build bundle --release`.

Security limits: local endpoint is an injected predicate, not DNS/network
verification. A production transport must reject redirects, public/remote
addresses, proxy fallback and credential leakage. A timed-out or cancelled
operation may have been dispatched; callers must not retry a physical operation
without fresh state inspection and approval. Cancel/restart fences responses,
not remote side effects. No persistent migration is needed because this module
stores nothing. Roll back by disabling its opt-in flag or dropping the caller
registration. No new UI or ActionLog integration is claimed yet.
