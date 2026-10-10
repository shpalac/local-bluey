# Host reload containment proof

Generated with `HOST_PIXELS=1 FLUTTER_ROOT=<sdk> flutter test test/host_reload_notice_test.dart`.

The failure/retry/recovery images show the actual shared HostReloadNotice on FaceScreen inside a synthetic Scaffold. The onboarding images show the same notice plus actual OnboardingScreen with injected false permission checks and mock preferences. Fonts/icons loaded for readable inspection. These are widget evidence, not MacHome startup integration or native permission/provider readiness evidence.

Controller fixtures enter actual BrainHostState load/refusal/build failure and retry with retained snapshot, plus stale/error/success/retry/dispose and reentrant ordering fixtures. MacHome call site coverage is a source-wiring assertion, not a mounted native MacHome test.

Containment does not change BrainHostState policy: a retained remote provider after a failed privacy preference read remains a separate policy gap. No network fail-closed claim.
