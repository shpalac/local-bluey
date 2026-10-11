# MCP containment draft

Audit: 2026-10-11. Refs #583. Main `5a0304a`, including accepted [MCP stdio draft](MCP_STDIO_CONTRACT_DRAFT.md) from PR #641. **DRAFT, first-stage preparation only.** #581 implementation, #554 privacy decisions and existing 351/retained-brain gates remain unresolved. No process launched, server installed, permission/credential/network/entitlement changed or full #583 acceptance claimed.

## Answer and current boundary

Do not enable local MCP servers until an independently enforced launch/containment boundary is selected and tested. Stdio limits the transport route, not a child's filesystem, environment or sockets. An app allowlist and app egress log cannot make a hostile process local-only. Unknown containment must remain unavailable, not silently degrade to bare execution.

Complete current [Linux host base](../lib/services/linux_host_base.dart), [X11](../lib/services/linux_x11_host_control.dart), [portal host](../lib/services/linux_portal_host_control.dart), [HostControl](../lib/services/host_control.dart), [SafetyGate](../lib/services/safety_gate.dart), [runner](../lib/services/request_runner.dart), [egress](../lib/services/egress_monitor.dart), [ActionLog](../lib/services/action_log.dart), [registry](../lib/services/data_registry.dart) and Mac entitlements were reviewed. There is no current MCP process owner or enforced per-server network policy in these sources. The accepted #581 draft is a proposed contract, not a runtime.

LinuxHostControlBase defaults to Process.run and searches helpers on PATH. X11 uses argv, avoiding ordinary shell interpolation, but the injected ProcessRunner returns only a Future of ProcessResult: no retained child handle/tree owner, environment isolation or shutdown evidence. Portal timeout bounds an awaited result, not termination. These GUI helpers are existing trusted host behavior, not an MCP sandbox to reuse for arbitrary servers.

Both [debug](../macos/Runner/DebugProfile.entitlements) and [release](../macos/Runner/Release.entitlements) explicitly set app-sandbox=false and network client/server=true. Apple documents that sandbox capability keys have no sandbox effect when App Sandbox is disabled. Do not infer child confinement from those booleans or toggle them in this slice. A signed helper/XPC/container strategy needs separate platform/design review compatible with existing screen/input capabilities.

## Threat model and proposed disabled launch contract

Threats: malicious/substituted executable or dependency; honest overcollecting server; server-output prompt injection; inherited credentials/private files; descendant escape; raw stdout/stderr leak; direct sockets/DNS or proxy bypass; stalled worker after Stop; crash/restart/action replay; approval or temporary-file residue after delete. A compromised host/admin is outside the proposed app boundary; disclose that limit rather than promising protection from all attackers.

Proposed `ContainmentProfile` binds reviewed server revision/executable digest to platform mechanism version, filesystem roots/read-write scope, environment names, network policy, process/resource/output limits and consent revision. This is not an implemented type. Default denies launch; unknown mechanism/permission/identity fails closed before spawn. Approved identity does not grant every tool operation. Keep #581 process ownership and #582 tool admission separate from containment.

- Absolute executable and argv, no shell/package-manager command, no mutable latest/PATH substitution. Validate path/identity and symlink/replacement race at launch through the selected native owner; checks alone are not a universal TOCTOU proof.
- Environment starts empty/explicit minimum; Dart's includeParentEnvironment defaults true and must not be inherited by accident. No broad keychain/home/browser/SSH/cloud token mounts. No credential collection in this draft. Windows .bat/.cmd can invoke shell parsing even when runInShell=false; deny them in a no-shell profile rather than assuming argv is enough.
- Private per-server temporary directory with narrow access, bounded disk/output/CPU/memory/process count, no arbitrary inherited descriptors. No host home mount; explicit reviewed input/output broker. Avoid server text/path labels in permission prompts without validation.
- Launch only inside confirmed containment. Failed network/filesystem/process boundary cannot fall back to an unsandboxed server. No elevated helper, privileged container setup, permission dialog or new network rule is authorized by this plan.

## Platform options, not selected deployments

| Platform option | Source-grounded mechanism | What still needs evidence |
| --- | --- | --- |
| Linux namespaces plus policy/resource owner | Namespace APIs isolate selected resources; network/mount/PID/user roles are distinct. cgroup-v2 can account/limit a process group and exposes cgroup.kill for its subtree. | Actual user/delegation/kernel support, immutable launch/namespace membership, restricted mounts, capabilities/syscalls, network enforcement and descendant escape tests. A namespace label or process group alone is not a filesystem/network policy. |
| Windows Job Object plus least-privilege/network boundary | Associated CreateProcess children normally join a job; breakaway settings change this. Kill-on-job-close/TerminateJobObject cover associated processes/jobs. | Associate before untrusted code executes, forbid breakaway, validate creation paths and actual membership/exit. Job accounting/termination is not a full file/credential/network sandbox; selected token/app-container/firewall boundary remains unreviewed. |
| macOS reviewed signed helper/XPC or separate isolation | Apple describes per-target App Sandbox and prefers XPC for privilege separation; child inheritance has specific entitlement rules. | Current app unsandboxed. Selected helper signing/packaging/access broker, descendants/network restrictions and real Mac evidence remain required. Do not claim inheritance from current app or deploy an undocumented sandbox command. |
| Container/VM wrapper | MCP local-security guidance offers isolated filesystem/environment/network patterns. | Availability, cost, updates, minimal mounts, capabilities, no privileged host socket and platform support. Not an automatic install or proof against host/admin compromise. |

No platform default is selected. Unsupported platform/denied permission/broken boundary returns typed unavailable with visible reason. Mobile is not silently treated as a desktop process host. CI fake profiles do not certify OS isolation.

## Cancellation, crash and deletion

Keep one lifecycle owner per reviewed server generation. Proposed states validating, isolated-ready, launching, active, cancelling, terminated, termination-unverified, failed. Pending Stop/revoke/delete invalidates generation first, stops admission, cancels protocol requests, closes stdin and waits a bounded grace, then escalates through the selected tree owner and verifies exit/membership cleanup. Numeric grace/resource values in #581 remain suggestions, not measured guarantees.

Dart Process.kill returns signal-delivery success, not exit or descendant confirmation; await exitCode and independent tree/accounting evidence. Normal child can outlive a parent exit, and detached modes further weaken ownership, so no detached launch. A malicious child may fork/daemonize or ignore protocol cancellation; child-PID kill alone is inadequate. If escalation fails or membership is uncertain, show termination-unverified and retain narrow recovery state; do not say 'stopped' or delete the evidence needed to finish cleanup. No rollback of completed external actions.

Crash must not auto-replay an uncertain action. A fresh approved generation can restart only under the selected recovery/idempotency contract. Revoke/delete prevents old delayed output from reaching brain/tools and blocks replacement launch until containment revalidated. Registry clear should terminate first and report failure before claiming descriptors/templates/temporary files removed. Preserve failed-delete truth and exclude remote-service data/physical erasure promises. Persistent approval/retention decisions await #554/#351.

## Egress visibility versus enforcement

Current EgressMonitor records selected caller metadata: parsed host, label, caller amount and time. Brain nonstream rows follow responses; STT/TTS/check rows precede sends. Amounts mix string lengths/file bytes/zero. Streams and Diagnostics have no record site. The log is bounded 300 rows/30 days and ordered against deletion, not all sockets or a transmission receipt. A subprocess's direct network activity is outside those selected app calls. Empty history is not no traffic, local endpoint names are not verified effective destinations.

Proposed separate containment audit reports scope explicitly: server/profile/generation, denied or permitted attempt, observation mechanism, timestamp and typed outcome. A broker can observe its mediated requests; OS enforcement can report permitted/denied attempts within its coverage. Neither should fabricate host/wire-byte receipts when only a policy decision is known. Direct DNS/socket/IPv6/proxy/child escapes must be denied or observed by the selected enforcement layer, not trusted to cooperative server logs. No raw URLs with credentials, headers, environment, args, stderr, tool payload or user files retained by default.

'Local-only' requires selected enforceable policy for that server, including loopback, DNS and proxy semantics; it is not transport locality. An approval to launch locally cannot authorize remote egress. Broader allowed endpoints need explicit scope and effective-destination checks. Unobservable attempted activity is 'coverage unavailable', not a count of zero. Host-wide telemetry is a separate sensitive monitoring decision, not this draft's default.

## Fake-only tests and real evidence boundary

Next independent contracts can use fabricated process/network/storage owners, no privileged change or third-party install:

- Unknown/mismatched/replaced executable, unsupported boundary, revoked approval and missing consent deny before spawn; no unsafe fallback or inherited environment.
- Windows batch/shell path rejected; unexpected descriptor/mount/resource profile rejected; denied access UI carries only verified scope and supports RTL/a11y in a later selected UI slice.
- Held launch/call/Stop/delete/kill-reset, late output and forked-child model; signal delivered but child alive remains unverified, escalation failure does not report completion.
- Broker permitted/denied attempt and direct-child unobserved event stay distinct; missing telemetry never becomes no-egress; malformed private event fields omitted.
- Bounded stdout/stderr/CPU/disk/fork pressure, crash/restart/no automatic replay, failed cleanup and reopened state. Failure should preserve narrow cleanup identifiers, not raw payloads.

A real platform lane must additionally demonstrate forbidden file/keychain/env/socket access denied, DNS/IPv6/proxy and fork escape blocked, tree exit confirmed, quotas enforced, permissions/signing/packaging valid and offline launch/revoke/delete reliable. Fake tests only verify app contracts; no 'proven sandbox' or universal no-egress claim. Keep required CI free/tiny with no native privilege/TCC/hardware assumptions or scheduled #160/paid runner activation.

## Fresh validation and remaining gates

**194 unchanged tests passed**, 0 new, across linux_x11_host_control, linux_portal_host_control, host_control, safety_gate, safety_gate_lifecycle, request_runner, egress_monitor, egress_metadata_boundary, egress_registry_clear, privacy_guard, action_log and data_registry. Fake GUI/process/metadata/deletion/runner boundaries only, not OS containment or hostile-server tests. Exact-head analysis/format/static/test/linux/security/docs and manager review remain PR gates.

No selected containment, firewall, sandbox entitlement, process owner, credential broker or production adapter implemented. #581/554 dependencies remain and generic #583 implementation checkboxes are not completed by this draft. No shared architecture/README/ACCEPTANCE_MAP edits or issue closure.

## Sources

Fetched 2026-10-11; official/API/OS documentation plus accepted project source. These are reference facts, not launch/install/permission instructions.

- [MCP local-server security](https://modelcontextprotocol.io/docs/draft/tutorials/security/local-server-security): protocol versus child process/filesystem/environment/network trust.
- [MCP stdio](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/stdio): cooperative shutdown/cancellation, not isolation.
- [Dart Process.start](https://api.dart.dev/dart-io/Process/start.html): environment defaults, shell/Windows batch and process modes.
- [Dart Process.kill](https://api.dart.dev/dart-io/Process/kill.html): delivered signal versus confirmed exit.
- [Linux namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) and [cgroup-v2](https://kernel.org/doc/Documentation/admin-guide/cgroup-v2.rst): distinct isolation/resource/accounting/kill mechanisms.
- [Windows Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects) and [TerminateJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-terminatejobobject): membership/breakaway/termination scope.
- [Apple sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) and [protecting user data](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox.md): per-target/signed helper constraints, not current app confinement.
