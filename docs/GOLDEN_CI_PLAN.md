# Golden screenshot CI proposal

Audit 2026-10-11, main `656297d`. Refs #603. DRAFT/UNADOPTED: preparation only, not new baselines, CI wiring, comparison tolerance or hardware acceptance. [#593](https://github.com/shpalac/local-bluey/issues/593) remains OPEN/unassigned. Sole new doc; no UI/font/asset/test/workflow/source/install/schedule/security changes or shared docs edits. Owner native/paid/self-hosted #160/privacy #351/retained-operation gates remain separate.

## Decision and current evidence

Reuse the existing golden harness, preserving exact decoded-pixel comparison and explicit review. Do not regenerate baselines to hide a failure. Keep generated mock captures distinct from hardware, simulator process screenshots and native permission acceptance. This draft selects no exception, tolerance, artifact audience or retention policy.

Read complete [harness](../test/screenshots/screenshot_harness_test.dart), [regenerator](../tool/regenerate_screenshots.sh), [fonts](FONTS.md), [CI](../.github/workflows/ci.yml), [motion helper](../lib/ui/motion.dart), face/onboarding/settings sources, relevant fixtures and README. Current source history `61bd867` and [PR294](https://github.com/shpalac/local-bluey/pull/294) preserve original #279 mock labels; live issue/PR279 were not resolvable. No competing open golden/screenshot PR was found in the bounded live open-PR inventory. Reporting/release/native plans are preparation, not adopted gates.

| Current source | Actual behavior | Limit |
| --- | --- | --- |
| Golden harness | 21 PNG baselines; fake readiness/denied permission checker, mock preferences, English/Hebrew, light/dark, explicit 720x520/1360x845/1920x1080 variants, DPR1 where size is set | Unspecified-size shots use test defaults; not a complete theme/locale/size/state Cartesian matrix or real permission test |
| Text and scrolling | 1x/2x onboarding; Hebrew RTL light and compact dark2x; scrolled-bottom shots and action containment assertions | Initial2x viewport can end mid-card; Hebrew needs native-speaker review, no complete accessibility proof |
| Fonts | BlueyRoboto bundled asset, test-only NotoSansHebrew; MaterialIcons loaded from FLUTTER_ROOT or explicit failure | Font hashes alone do not pin renderer, engine, runner, fallback or OS settings; font/platform/version variation matters |
| Timing and motion | Fixed pumps plus200ms real async wait; perpetual diagnostics avoids pumpAndSettle; face transition reads disableAnimations | Harness has no explicit reduced-motion variant; fixed waits do not establish completion/determinism. App helper is not platform-wide reduced-motion proof |
| CI and regeneration | Both test/Linux lanes call flutter test, so existing harness is included; test logs/coverage uploaded, simulator launch artifact separate. Regenerator uses --update-goldens then copies docs images | No dedicated sanitized golden-diff failure upload or baseline manifest. Regenerator mutates baselines/docs and is not run for this plan |

Roboto hash verified `79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95`; Hebrew hash `436900d5ad77d33e4234247f3076eaecd25b92b9bea0519514f684140e3566a7`, matching FONTS.md. SDK pin is3.47.6. Current source is authoritative; comments promising two-run identity are not a fresh reproducibility receipt. Existing golden comparisons passed in this audit, but no baseline was regenerated or current full-suite acceptance inferred.

## Proposed typed run and baseline contract

A future `GoldenRunIdentity` should bind repository, PR head, actual checked-out merge SHA, workflow/job/run/attempt, SDK+engine, runner OS/image/architecture, renderer, comparator/version and exact command. `GoldenCaseIdentity` adds fixture/source hash, baseline relative key/hash/dimensions, fonts+icons hashes, physical/logical size+DPR, theme, locale+direction, text scaler, motion flags and exact pump/async-completion sequence. Missing inputs are unavailable evidence, never substituted defaults.

A future `GoldenResult` distinguishes passed exact pixels, mismatch, missing baseline, decode/font/setup failure, incomplete/timeout/cancelled, comparator bypass and update mode. Record completion separately from exit code. A non-comparing `flutter run` or --update-goldens receipt is not a passing comparison. Existing bytes, decoded pixel equality and visual inspection are different checks; require the appropriate one without claiming universal cross-platform byte identity.

| Proposed stage | Review and negative fixtures before implementation |
| --- | --- |
| Prepare offline fixtures | Allow only fabricated text, local fake stores/services and approved font assets. Reject private paths, real endpoints, credentials, screenshots/audio from users or native capture. Test denied/offline/setup failure without live permission requests |
| Compare | Preserve existing baseline; reject absent/corrupt PNG, wrong dimensions, wrong identity, missing font, unexpected renderer/platform, bypass/update mode and terminal incomplete result. No tolerance or automatic baseline replacement |
| Review complete pixels | Inspect master, actual, isolated and masked diff at readable scale; record exact case/identity and clipping/wrapping/RTL/action visibility findings. OCR-only, thumbnails or a cropped viewport cannot prove the rest of the image |
| Publish failure evidence | Allowlist fabricated case paths and identity metadata, bounded file sizes/counts, explicit manifest and no private source paths. Inspect full pixels before release; unknown provenance is withheld, not silently blurred or logged |
| Settle/cancel | Own render/decode/file futures; timeout or superseding run is unavailable, not pass. Join entered work before cleanup, avoid late upload and preserve original attempt; cleanup failure is explicit |

## Baseline change, privacy and rollback

Future baseline updates need an independently reviewed source/UI change, pinned generation environment, before/after complete pixels, attributable rationale, explicit manager disposition and owner authority when changing acceptance/privacy/native/security or paid execution. Regeneration is separate from comparison. Keep original failures and source commits; no blanket update-goldens, retry-to-green or quarantine adoption through this plan.

Sanitized artifacts can still disclose private pixels or filenames. Restrict fixtures before rendering; omit raw user captures and avoid broad glob uploads. Audience, retention and deletion need a scoped decision, not inference from upload availability. GitHub artifact immutability/digest is not proof of privacy, correct baseline identity or visual review. Cancelled runs retain honest receipts; unavailable artifacts never become successful comparison evidence.

Rollback a future implementation by reverting the reviewed wiring/comparator changes while keeping original baseline history and failure receipt; confirm required checks remain honest and prevent late writers/uploads. No rollback command, deletion, scheduled job, new test, baseline update or artifact policy was executed here. Current #649 Linux failure is a separate unchanged fixture investigation, not evidence that this golden harness is flaky.

## Validation and primary sources

Fresh unchanged command: `flutter test test/screenshots/screenshot_harness_test.dart test/theme_test.dart test/onboarding_test.dart test/onboarding_checks_test.dart --reporter expanded`:52 passed,0 new tests. Analyze clean; format273/0 changed;4 offline ci_metrics Python fixtures pass. Generated plugin/local SDK paths restored, no test/assets/baseline changes. Required exact-head static/test/linux/security/docs and manager APPROVED remain necessary before auto/squash; current PR CI is recorded separately.

- [matchesGoldenFile](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html): image/finder boundary and custom font/platform/Flutter-version caveats.
- [LocalFileComparator](https://api.flutter.dev/flutter/flutter_test/LocalFileComparator-class.html): exact decoded PNG pixels, failure master/test/isolated/masked images and update mode.
- [Comparator selection](https://api.flutter.dev/flutter/flutter_test/goldenFileComparator.html): flutter test comparison versus trivial flutter run behavior; custom tolerance is possible, not selected.
- [Flutter source](https://github.com/flutter/flutter/blob/main/packages/flutter_test/lib/src/goldens.dart): current upstream comparator/update semantics, not a claim that upstream main equals the pinned SDK.
- [pumpAndSettle](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html): scheduled frames and infinite-animation limits, not real IO completion.
- [disableAnimations](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html): current platform/custom-widget distinctions; verify pinned SDK behavior before future implementation, no new OS acceptance claim.
- [GitHub artifacts](https://docs.github.com/en/actions/using-workflows/storing-workflow-data-as-artifacts): storage/retention/digest mechanics, not privacy certification. Fetched for the prior reporting audit, reread for this plan.
