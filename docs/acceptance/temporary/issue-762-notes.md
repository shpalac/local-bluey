# Issue #762 — SafetyGateRuntime second wave

The runtime recursively redacts secret-like map keys (`token`, `secret`, `password`, `private_key`) at every depth, including maps embedded within lists. It returns a separate map/list tree so caller-owned collections are not modified. Scalar values and safe keys remain unchanged.

`McpCancellationSignal` allows callers to cancel while a gate invocation is awaiting permission or tool completion. Cancellation ends the caller's wait with `McpToolFailure.cancelled`. **It is best-effort once execution starts**: it cannot revoke permission already granted, interrupt a running MCP tool, recall an executed side effect, or guarantee the underlying transport stops. The legacy `isCancelled` callback remains a pre-execution check for backwards compatibility; callers requiring in-flight cancellation must pass a signal.

The underlying gate remains responsible for permission decisions, schema validation and timeouts. This slice does not launch a live MCP process or validate native macOS/TCC behavior. Those checks are explicitly deferred to manual platform/integration validation.

Verification: `dart format --output=none --set-exit-if-changed lib/mcp test/mcp`, `flutter analyze lib/mcp test/mcp`, `flutter test test/mcp/safety_gate_runtime_test.dart`. Live process and device checks are **manual/gap**, not automated evidence.
