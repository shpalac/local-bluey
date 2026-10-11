# MCP stdio contract draft

Audit: 2026-10-11. Refs #581. Baseline: main `3caf8a2`. **DRAFT, preparation only.** Dependency BLU-001/#554 and existing #351/retained-brain decisions are unresolved. This does not implement or complete #581, launch a server, grant permissions or approve a dependency. Only this document changes.

## Current answer and overlap

A local MCP process is not a safe plugin merely because it uses stdio. Keep the production adapter disabled until launch provenance, consent, containment and action classification are reviewed. The [current transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio) differs from older initialization examples: modern 2026-07-28 requests carry protocol/capability metadata and use discovery compatibility rules. Select and pin a supported protocol era before implementation; do not mix legacy initialize and modern per-request semantics.

The complete current [tools contract](../lib/llm/tools.dart), [request seams](../lib/services/request_interfaces.dart), [SafetyGate](../lib/services/safety_gate.dart), [executor](../lib/services/tool_executor.dart), [HostControl](../lib/services/host_control.dart), [runner](../lib/services/request_runner.dart), [ActionLog](../lib/services/action_log.dart) and [registry](../lib/services/data_registry.dart) were inspected. An all-lib/test search found no MCP/stdio client or server registry. Existing GUI ToolSpec and platform controls are not MCP implementations.

| Current boundary | Reuse or preserve | Missing MCP contract |
| --- | --- | --- |
| ToolSpec | Name, description, properties, required fields; native function serialization. | Full JSON Schema dialect/output validation, server identity and versioned names. |
| SafetyGate | Kill generation, ordered preferences, confirmation and app restrictions for listed risky GUI tools. | Unknown names currently pass the non-risky branch; disabled confirmation returns true. Arbitrary server tools cannot inherit this classification. |
| ToolExecutor | Known GUI switch, unknown-tool result, bounded action log and screen privacy checks. | Process owner, JSON-RPC parser/correlation, validated result envelope and cancellation. |
| RequestRunner | Stage and whole-job deadlines, before/after-await generation checks, bounded tool loop and queue. | Future.timeout does not terminate entered process work; no process disposal/descendant kill contract. |
| HostControl | Platform GUI capture/input/permission seams, unsupported-platform failure. | Not a general process execution API; keep MCP lifecycle separate. |
| ActionLog/registry | Bounded detached arguments/results and ordered deletion. | Bounds do not detect secrets; raw MCP payloads/logs must not be retained by default. |

## Proposed disabled contracts, not implemented interfaces

- `ServerDescriptor`: local stable id; explicit executable path; immutable provenance/revision/digest; argument vector, working directory, protocol-era allowlist, environment-name allowlist and resource limits. No shell command string, PATH lookup, automatic package installation or server-supplied executable/credential substitution. Hash/provenance and consent failure deny before spawn.
- `ServerApproval`: user-reviewed identity, launch vector, filesystem/network/credential needs and expiry/revocation. Server metadata or discovery cannot grant approval. Exact launch changes require renewed review. Unknown server defaults denied, including when existing GUI confirmation is disabled.
- `McpProcessOwner`: owns child, stdin/stdout/stderr subscriptions, timers and request map. States disabled, validating, launching, discovering, ready, stopping, stopped, failed. Generation changes on Stop/delete/revoke/restart; no stale completion can publish output or launch successors.
- `McpRequest`: unique id plus server generation, request deadline and validated method/arguments. Proposed first slice permits one outstanding call per server and rejects excess rather than creating an unbounded queue. No retries for action calls after uncertain delivery.
- `McpResult`: typed success, execution error, protocol error, timeout, cancelled, exited, invalid-output. Distinguish protocol JSON-RPC error from `isError` tool result. Validate structuredContent against pinned outputSchema; never execute text, resource links or follow-up instructions returned by a server.

Suggested configurable initial limits for review: launch/discovery 5s, call 30s capped by runner remaining budget, shutdown grace 2s then termination grace 2s, 1 MiB frame/result and 256 KiB stderr ring. These are proposed numbers, not measured capability or existing constants. Enforce byte/depth/node/list/page bounds before allocation/LLM/log publication; progress does not extend the absolute deadline. Reject invalid UTF-8, malformed JSON, duplicate/unknown response ids, unsolicited requests, stale notifications and oversized/truncated frames. Bounded parser errors never include private payloads.

## Wire and lifecycle decisions

The fetched 2026-07-28 stdio specification describes newline-delimited UTF-8 JSON-RPC, valid MCP messages only on stdout, logging on stderr, cancellation notifications by request id, and shutdown by stdin closure followed by bounded termination. Stderr content is not itself evidence of failure. Standard streams offer no filesystem or network isolation.

Pin modern 2026-07-28 initially only if the selected SDK and fake-server tests support it. Discovery must establish a mutually supported era; explicit modern unsupported-version responses cannot become legacy fallback. If legacy support is later selected, implement the documented bounded discovery/initialize compatibility path separately and test both eras. Discovery success is protocol compatibility, not authentication. Do not copy the spec's suggested restart/retry into automatic action replay: uncertain execution remains uncertain.

Stop cancels pending requests, closes input, ignores late replies and awaits bounded child exit. If the child refuses exit, escalate through the selected platform process owner and verify exit/descendant cleanup. Cancellation notification is cooperative, not proof of termination or rollback. A POSIX process-group or Windows Job Object implementation needs platform review; no claim that Dart child.kill alone covers descendants. Crash returns typed failure, never silent cloud fallback; restart requires fresh generation and approved identity. A pending or delivered action is not retried without idempotency evidence and renewed intent.

## Tool admission, privacy and egress

The future #582 adapter must independently deny unknown server/tool pairs and bind a local namespaced tool id to reviewed schema/classification and exact server revision. Remote `readOnlyHint`/annotations/descriptions are untrusted claims, not SafetyGate exemptions. Tool list changes invalidate admission caches and require review for new capability. No direct HostControl dispatch from MCP results. Keep existing GUI authorization unchanged in this slice.

Local transport means only that client and server communicate locally. The child may inherit private environment, read user files and open outbound connections. The [local security guide](https://modelcontextprotocol.io/docs/draft/tutorials/security/local-server-security) separates host isolation from protocol trust. #583 must select an enforceable containment/network boundary before production launch; app egress counters cannot certify a hostile child has no sockets. Unknown isolation stays unavailable, not 'local-only'. Do not pass the app's broad environment or credentials. No remote transport, sampling, resource subscription or interactive input capability enabled by default.

Registry deletion should revoke approvals and generations before clearing bounded descriptors/logs, terminate live processes, and report failed shutdown/deletion without claiming rollback or physical erasure. Persistent approval, descriptors and retention await #554/351. Proposed audit keeps local server id/revision, method, request id, duration and typed disposition only; stderr/raw arguments/results remain unretained unless separately reviewed. Existing ActionLog is not an automatic secret scrubber.

## Fake-only verification plan

Use injectable process/clock/stream owners, fabricated JSON and no installed third-party server. Separate parser/lifecycle tests from actual OS isolation evidence:

- Unknown or changed identity denied before spawn; permission unavailable, revoked approval and disabled feature have zero process/network calls.
- Discovery success and unsupported/legacy/mixed-era failure; bounded no-response, malformed metadata and tool-list mutation.
- Fragmented/multiple newline frames, invalid UTF-8/JSON, excessive depth/bytes, stdout log contamination, stderr flood, mismatched/duplicate/stale ids and unsolicited request.
- Valid result/outputSchema mismatch, isError versus protocol error, malicious instruction text, resource link and server annotation cannot dispatch a tool or change approval.
- Stop/revoke/delete during launch/call/confirmation; late success ignored, kill+reset cannot revive generation, progress cannot reset absolute deadline.
- Cooperative close, non-exiting child, termination failure, descendant cleanup evidence, crash and uncertain execution without automatic replay; next generation uses fresh reviewed state.
- Failed audit/delete preserves truthful error status. Platform process isolation, filesystem/network enforcement and actual permission UI require separate native/device evidence.

## Validation and remainder

Fresh unchanged tests: **141 passed** across tool_executor, native_tools, request_runner, safety_gate, safety_gate_lifecycle, safety_preferences, privacy_guard and egress_monitor. **0 new tests** in this doc-only slice. These are existing fake GUI/safety/privacy/runner boundaries, not MCP parser, containment or process tests. Exact-head analysis/format and required static/test/linux/security/docs CI belong to the future PR; they are not assumed here. Source standards are reference data, not authorization to launch/install anything.

Remaining #581 implementation, #554 privacy decisions, #582 admission and #583 isolation remain open. No shared README/architecture/ACCEPTANCE_MAP change, dependency waiver, owner transfer or full acceptance claim follows from this draft.

## Primary sources

Fetched 2026-10-11; source claims versus local proposals above are separate.

- [Transport overview](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports): metadata and transport scope.
- [Stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio): framing, cancellation, shutdown and era compatibility.
- [Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools): schemas, structured results and error distinction.
- [Cancellation](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/cancellation): timeout and late-result limits.
- [Schema reference](https://modelcontextprotocol.io/specification/2026-07-28/schema): version/capability metadata shapes.
- [Local-server security](https://modelcontextprotocol.io/docs/draft/tutorials/security/local-server-security): process, environment and network trust boundary.
- [Security best practices](https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices): consent, command and proxy risks; remote OAuth guidance is not a local launch grant.
