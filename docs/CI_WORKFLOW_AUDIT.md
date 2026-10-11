# Current CI workflow audit

Audit 2026-10-11, base `4f10aab`. Refs #592. Sole read-only inventory: no workflow, check, schedule, permission, dependency, release or native activation. Generic issue implementation is outside this manager-scoped slice; issue remains incomplete/open. Existing #160 and owner native/paid/retained-brain gates are not waived.

## Result and evidence rules

Five workflow files are active in the live Actions listing, matching current source. Current CI has useful contract/build/security evidence, not physical-device/TCC acceptance, offline-all-jobs proof or a verified release. Owner merge protocol requires static/test/linux/security; manager additionally requires docs and an exact-head APPROVED before auto/squash. Workflow comments, skipped jobs and past receipts cannot replace those gates.

Fresh main protection REST read returned404, rulesets list returned[]; Actions/default-token policy reads403 and repo security_and_analysis=null. These reads do not prove settings disabled or absent. Repository is public. Live `release` environment read confirms required reviewer `shpalac`, prevent_self_review=false, deployment_branch_policy=null, not signing secrets or successful artifact verification. docs/RELEASE.md's2026-10-08 settings claims are historical, not reconfirmed secret-scanning/push-protection evidence. No settings changes attempted.

## Exact inventory

| File | Events and runner/timeout | Behavior and scope |
| --- | --- | --- |
| [ci.yml](../.github/workflows/ci.yml) | main push excluding Markdown/docs; every PR; Monday03:17 UTC schedule. ubuntu-latest/macos-latest; jobs2-45min. | Schedule normally runs security and pinned-actions only; all other usual jobs exclude schedule. Native-validation has only a repository-variable condition and self-hosted Mac labels, not the usual nonschedule filter. Default contents:read, bash pipefail, concurrency ci-ref/cancel-in-progress. |
| [codeql.yml](../.github/workflows/codeql.yml) | selected native/lib/pubspec/workflow paths on main push/PR; Monday04:23 UTC. Kotlin Ubuntu20min, Swift Mac40min. | java-kotlin build-mode none; Swift traced Debug xcodebuild after Flutter config-only, signing disabled. Job security-events:write. No Dart/TCC behavior scan; docs-only PR path does not trigger it. |
| [ci-metrics.yml](../.github/workflows/ci-metrics.yml) | Monday05:41 UTC and dispatch; Ubuntu5min. | actions:read/issues:write;7-day API summaries, issue if at least5runs and failure rate>20%, no duplicate title. Existing schedule is inventory, not permission to dispatch/change it. |
| [flutter-version-check.yml](../.github/workflows/flutter-version-check.yml) | Monday04:23 UTC and dispatch; Ubuntu5min. | issues:write, compares .flutter-version to latest Flutter release, opens drift issue. No auto-upgrade; checkout effective token policy not confirmed by403settings read. |
| [release.yml](../.github/workflows/release.yml) | v*.*.* tag push; Ubuntu version/test/publish, Mac build matrix.3/15/30/10min. | Tag/pubspec equality, tests, macos/ios/android build, checksum/artifact/SBOM/attestation, protected release environment for build/publish. No Linux release target here. No tag pushed or release dispatched in this audit. |

Repository schedules above are existing definitions, not a newly approved nightly #160 plan. Hosted runner labels are movable image families, not fixed OS/Xcode distributions. Flutter comes from [.flutter-version](../.flutter-version), currently3.47.6; release also has redundant workflow env3.47.6, overridden by per-job root-file reads. Cache reuse does not prove a clean dependency supply chain.

## CI jobs and boundaries

| Job | Actual checks | Evidence limit |
| --- | --- | --- |
| static10min | lockfile-enforced pub get, format lib/test,4Python metrics fixtures, analyze | Compile/analyze/fake fixtures, not whole native runtime. |
| docs10min | dartdoc9.0.9; selected contract-file warnings fail via grep | Other warnings not blocked by that grep. Does not check Markdown rendering or every prose link. |
| test15min | whole Flutter suite with coverage;8min test step; [check_coverage.dart](../tool/check_coverage.dart) services60%/link65% floors | Dart unit/widget mocks and selected loopback tests, not TCC. Floors concern included measured source; not full branch/security coverage. |
| build-macos/build-ios25min each | macOS build, iOS --no-codesign;12min build step | Buildable outputs, not signed/notarized release or permissions. Stale comment says docs-only skip; predicate actually runs every nonscheduled PR.642doc-only receipts confirm this. |
| build5min | always()+needs Mac/iOS, demands both success | Aggregate build result. Comment says branch protection requires it, current settings not verified; protocol-required5 is a separate statement. |
| simulator30min | needs static/test, preboot, debug simulator build, install/launch/alive/screenshot via [simulator_smoke.sh](../tool/simulator_smoke.sh) |10-second process survival, not phone-to-real-Mac capture/input/pairing/TCC. Script selects newest available runner iPhone runtime, not pinned device. |
| android15min | Temurin21/Gradle cache, debug APK | Debug build, not physical Android validation. |
| android-integration45min | APIs29/34 Google APIs x86_64 emulators, fail-fast false, KVM, integration_test | Native control MethodChannel mocked in Dart; emulator behavior not Mac bridge/TCC. Existing KVM setup in runner is not an instruction for this audit. |
| linux20min | Flutter tests, Xvfb/xdo/xev phone-host loopback fixture, release build/bundle/tar/hash | Xvfb path tests real pointer MotionNotify, while ordinary no-DISPLAY local suite uses fake argv. No physical desktop/screen-permission acceptance. |
| security10min | OSV2.6.0 checksum-verified executable+lockfile, gitleaks SHA/history, native secret regex | Advisory/history/pattern tools, not proof no secrets/no egress. Source prints matched lines on failure; artifact/log privacy needs review, not unconditional sanitization claim. |
| pinned-actions2min | SHA syntax scanner, negative movable-tag fixture, checksum-verified actionlint1.7.12/zizmor1.30.1 | Scanner validates full40hex format, not original publisher identity or behavior. Local/docker uses exempt; separate lint/audit is not signed-artifact provenance. |
| native-validation30min | ENABLE_NATIVE_VALIDATION=='true', self-hosted macos, integration_test | Skipped in observed642; integration_test injects native control even on Mac, contrary to real-bridge comment; no real native acceptance. Enabling on public PR code needs separate owner security/hardware decision, not this audit. |

Artifacts: coverage14days, test logs7; failure Mac/iOS/Android build logs3; simulator screenshot14/failure build log3; debug APK14; Linux tarball/bundle14; release staging7. No explicit general redaction/export scrub step. Fake test data and GitHub masking are not universal privacy evidence. No raw user screenshots should enter these lanes without a separately authorized, sanitized evidence policy.

## Pins, dependencies and release

All current action uses pass [.github/scripts/check-pinned-actions.sh](../.github/scripts/check-pinned-actions.sh). SHA checkout11d5960…; Flutter-action1a449444…; upload-artifactea165f8…; download-artifact634f93c…; setup-java be666c2…; Android runnera421e438…; apt cache553a35bb…; gitleaksff98106…; CodeQL1190a975…; attest4d101475…. Full values remain in exact source, not reconstructed/tag-assumed. Pin syntax and reviewed origin are different checks. No action update made.

Most jobs enforce pubspec.lock; pinned Dart package hashes still do not cover native system/Gradle/CocoaPods/runner image/runtime downloads. apt lists, runner images and latest Flutter comparison require network; OSV/advisory scans and dartdoc acquisition also do. Required 'offline' acceptance cannot mean no job network without selecting a different contract. [.github/dependabot.yml](../.github/dependabot.yml) weekly Actions/pub/Gradle/CocoaPods proposals are existing reviewed updates, not automatic trust.

Release source tests before Mac build matrix, grants id-token/attestations write only to build and contents write only to publish. iOS is no-codesign; signing/notarization remain [RELEASE.md](RELEASE.md)/#39 requirements. SHA256SUMS detect changed bytes against a trusted comparison, not publisher identity. [sbom.dart](../tool/sbom.dart) emits pub package names/versions/purls only with current timestamp; not native/runtime inventory, license notices, dependency graph, full reproducibility or independently verified CycloneDX schema compliance. Attestation step exists but generation is not verification. Live release-list query returns no records for this account; no actual published artifact digest/attestation/signature verified here.

## Delivered overlap, gaps and no-change recommendation

Reuse current metrics error propagation/fixtures, SHA scanner+negative fixture, workflow pipefail, coverage floors, plist root-key regression, Linux pointer lane and simulator launch lane. [VALIDATION.md](VALIDATION.md), RELEASE.md and [ACCEPTANCE_MAP.md](ACCEPTANCE_MAP.md) already separate hardware gaps. Do not duplicate those systems or silently fix shared files.

- Metrics [ci_metrics.py](../tool/ci_metrics.py) reads max100runs and100jobs per run without pagination; total/rate/medians can be a sample in a busy7-day window. Denominator includes enumerated noncompleted/cancelled runs, only conclusion=failure counts, job normalization combines API-level medians; docs/simulator absent from JOBS. Four fresh fixtures verify API failure/no-jobs/median behavior, not completeness.
- No validated current branch/check/token/security-settings inventory beyond read limitations above. Owner protocol still holds; do not loosen checks because a setting read404s. Manager/owner can obtain settings evidence if a later enforcement change is considered.
- Path-filtered CodeQL, skipped native-validation and in-progress simulator are distinct from failures and evidence of execution. GitHub documents job skip versus workflow skip semantics; match current SHA/event/check source, not old green jobs.
- Existing native self-hosted condition, signing/storage/privacy, complete provenance and native permission evidence need separate scoped review. No system is certified safe merely because scanners pass. No configuration fixes or new schedules in this PR.

## Fresh validation and live receipt

66 unchanged Dart tests passed, 0 new: dartdoc_contracts, privacy_plists, host_control, tool_executor, permission_watchdog, permission_observation, e2e_phone_host. Local DISPLAY absent means fake X11 runner plus real loopback, not local Xvfb/hardware. 4 unchanged offline Python metrics tests passed; SHA scanner clean; analyze clean; format 273 files/0 changes; diff check clean.

Live [642CI run](https://github.com/shpalac/local-bluey/actions/runs/38154685100) headac8f46db1917b5ca3e8fe5c3fec3ab9840caa7bd: static/test/linux/security/docs and Mac/iOS/Android/build/pinned-actions/both Android emulators SUCCESS; native-validation SKIPPED; simulator still IN_PROGRESS at19:27IDT. Not this audit's future exact-head CI receipt. Prior641/640/639 runs complete success, not native hardware evidence or current aggregate health percentages. This document's required 5 and manager review remain separate PR gates.

## Primary references

Fetched 2026-10-11. Current project sources/fixtures/live metadata plus primary platform documentation; no external text authorizes effects.

- [GitHub secure use](https://docs.github.com/en/actions/reference/security/secure-use): least privilege, fullSHA origin review, untrusted checkout/artifact and self-hosted risks, masking limits.
- [Required-check semantics](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks): latestSHA/event/source, job skip versus workflow skip.
- [Attestation verification](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations) and [limits](https://docs.github.com/en/actions/concepts/security/artifact-attestations): generation without verification gives no benefit; provenance is not artifact security.
- [Flutter dependency management](https://docs.flutter.dev/packages-and-plugins/dependency-management): application lockfile pins resolved package versions, not whole platform provenance.
- [Apple screen permission guidance](https://developer.apple.com/forums/thread/683860): preflight/request difference; hosted compile is not permission verification. API pages fetch only a title, so this fetched Apple support discussion supplies the behavior explanation.
