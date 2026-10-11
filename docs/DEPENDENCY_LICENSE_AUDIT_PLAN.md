# Dependency and license audit plan

Audit 2026-10-11, main `c7c2155`, including accepted [CI audit](CI_WORKFLOW_AUDIT.md). Refs #605. **DRAFT first-stage preparation**, not an implemented license gate or completed #605 acceptance. Sole new document, no dependency/install/archive/model download, action/workflow/security/permission/release/package change or new license commitment. Existing native/model/retained-brain/owner gates remain; no shared README/architecture/acceptance-map edits.

## Answer and inventory

Build a source-bound inventory with exact license/notice evidence, then let a reviewed distribution policy decide compatibility. Current lockfile and scanner/SBOM/model checks are useful inputs, not proof all shipped dependencies are licensed or safe. Missing/ambiguous evidence must stay needs-review, never 'MIT by default'. This audit identifies no confirmed incompatible dependency and does not legal-certify distribution.

Complete [pubspec](../pubspec.yaml)/[lock](../pubspec.lock), native build files, existing workflow/action/release inputs, [SBOM generator](../tool/sbom.dart), model core admission/fixtures and prior model/research/font/icon notices reviewed. Lock inventory: 120 packages, 14 direct main/4 direct dev/102 transitive; 113 hosted/7 SDK. Pubspec ranges are not resolved versions. Direct hosted locked set:

| Scope | Exact resolved versions | Evidence limit |
| --- | --- | --- |
| Main | audioplayers 6.8.1, clock 1.1.3, crypto 3.0.7, cupertino_icons 1.0.9, flutter_secure_storage 9.2.4, http 1.6.0, local_auth 2.3.0, nsd 5.0.1, path_provider 2.1.6, record 7.1.1, shared_preferences 2.5.5, tray_manager 0.2.4, window_manager 0.5.2 |113 hosted lock entries include archive SHA256; exact locked package/native graph must be matched, not latest package-page licenses. |
| Dev | fake_async 1.3.3, flutter_lints 6.0.0 | Test/build dependencies still matter to provenance, not assumed shipped or harmless. |
| SDK | flutter, flutter_test, flutter_driver, flutter_web_plugins, fuchsia_remote_debug_protocol, integration_test, sky_engine all 0.0.0 | SDK-source placeholders, not real pub versions/purls. Resolve against Flutter 3.47.6/toolchain revision, distinguish runtime from dev/test. |

Read-only local cache discovery found LICENSE files for all 113 hosted locked entries and hashed each license file for investigation. This is presence/cached-text evidence only: not an archive rehash, no full transitive/native license classification, no cache authenticity proof. A tree named package-version can be stale/modified. No packages downloaded to manufacture this finding; fresh normal lock-enforced pub get/tests are regression work, not an audit acquisition or upgrade.

## Primary exact-version license checks

Four representative direct dependencies were verified on their exact pub.dev license pages and complete corresponding cached texts, not score badges or latest versions:

| Package | Primary published terms | Why it matters |
| --- | --- | --- |
| [record 7.1.1](https://pub.dev/packages/record/versions/7.1.1/license) | BSD-3-Clause text, copyright openapi4j authors | Preserve actual attribution, do not rewrite surprising author/name to match package branding. Source/binary notice+disclaimer and nonendorsement conditions explicit. |
| [flutter_secure_storage 9.2.4](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4/license) | BSD-3-Clause, German Saprykin | This covers that package's published text, not every platform plugin/keychain/Keystore native dependency. |
| [clock 1.1.3](https://pub.dev/packages/clock/versions/1.1.3/license) | Apache-2.0 full text | Preserve license/attribution, modified-file notice and any applicable NOTICE file; patent/trademark clauses not erased by a permissive label. |
| [nsd 5.0.1](https://pub.dev/packages/nsd/versions/5.0.1/license) | MIT text, Sebastian Haberey and others | Retain copyright/license; runtime mDNS/native component provenance remains separate. |

Other direct local texts include MIT-labelled audioplayers/Cupertino/tray/window, Apache text fake_async and BSD-style Dart/Flutter package notices. Those are cached leads, not a live exact-source classification of all 15 direct hosted packages or 120 total. Do not promote a short header or a generic package publisher badge into redistribution clearance. Every transitive/platform/input must have its own exact-version text and identity, including bundled third-party notices inside a package.

Root [LICENSE](../LICENSE) is MIT for this repo, not a relicensing of dependencies. [FONTS.md](FONTS.md) records bundled Roboto Apache-2.0 and test-only Noto Hebrew OFL; exact local font hashes previously confirmed in #606 preparation, not a new full asset audit. [icon README](../assets/icons/README.md) records selected artwork/export workflow but is not a standalone upstream license/notice grant. Do not infer missing rights or incompatible licensing from that absence; preserve source-rights evidence as unknown until its original owner/artifact record is checked before distribution.

## Native, action, model and release coverage

[Android settings](../android/settings.gradle.kts) pin AGP 9.1.0/Kotlin 2.4.0; [wrapper](../android/gradle/wrapper/gradle-wrapper.properties) points to Gradle 9.3.1 with no distributionSha256Sum. No tracked Gradle verification metadata/locks or Apple Podfile.lock/Package.resolved found. [Mac Podfile](../macos/Podfile) delegates plugins to Flutter; iOS Podfile absent and pub get generates ephemeral Swift package state. These are resolver/input gaps, not evidence no native dependencies exist. Audit actual selected platform graph, system libraries/SDKs and redistribution terms before claiming native coverage. No pod/Gradle install or verification-metadata generation here.

All action uses pass current full-SHA syntax scanner, OSV/actionlint/zizmor downloads have source checksums, and Dependabot proposes reviewed updates. SHA syntax is not publisher/source/license verification; inspect each exact action/tool revision and its dependencies for build/provenance scope. Advisory clean is not a license finding. Existing [release workflow](../.github/workflows/release.yml) builds Mac/iOS/Android, hashes and attests, but no license gate/notice aggregation step. Public release listing returned no available records for this account; no actual shipped contents or notices verified. Signing/notarization/#39, native acceptance and environment authority remain separate.

Current [sbom.dart](../tool/sbom.dart) emits 120 name/version/pub-purl entries and timestamp, no license expressions/text hashes/native relationship graph; SDK 0.0.0 also becomes pub purls. It is an inventory sketch, not authoritative CycloneDX compliance or whole-platform license review. Current [model store](../lib/services/model_store.dart) rejects blank licenseNotice and validates install size/hash/backend; nonblank caller text is not verified legal terms. Ready/restart metadata is not new license verification or always rehashed bytes.

[Ivrit plan](IVRIT_MODEL_OPTION_PLAN.md) and [VAD/speaker research](VAD_SPEAKER_RESEARCH.md) already distinguish runtime/artifact/model/data permissions and immutable identities. Candidate Whisper/Silero/sherpa model weights, source runtime code and evaluation corpus can have different licenses/conditions. Those candidates are research, not installed licensed assets. Do not copy their current main-card label into an arbitrary converted model or dataset descriptor; require exact revision/files/full conditions/source digest. No model/corpus/audio acquisition or new notice acceptance in this slice.

## Proposed offline audit contract

A later manager-selected inert tool can consume fabricated/versioned local manifests only. Proposed record: schema version, package/component/source type, exact resolved version and source revision/archive digest, scope/platform/shipped/build-only classification, extracted license expression and full-text/NOTICE hashes+references, extraction confidence/provenance, reviewer policy revision and result. Preserve raw reviewed legal texts unchanged; no credentials/private paths/user files in reports. A tool may extract candidates, never silently decide legal meaning from branding. Deterministic evaluation pins schema/parser/policy revisions, stable sorted component keys/text hashes and canonical output; timestamp stays diagnostic, outside the decision digest. Bound file count/text size/depth and reject path traversal/symlinks outside fixture root. Explicit read/parse timeout or cancellation produces incomplete, never approved; no log of arbitrary source payload.

License expressions preserve AND/OR/WITH, exceptions, LicenseRef and parentheses using SPDX semantics; OR is a choice, AND cumulative requirements, WITH an addition/exception, not equivalent strings. Unknown/custom/missing/multiple/conflicting terms need explicit reviewed handling. A policy should name the intended distribution/linking/modification/notice requirements and approved exceptions. No universal allowlist guessed here. Approval of an audit document is not approval to accept new terms or install a package.

First acquisition/source comparison, if later authorized, can use the documented Hosted Pub Repository V2 exact-version metadata/archive_sha256 route and validate bytes against the locked digest before inspecting license files. Publisher metadata/scores are not license text. Cached extracted tree alone cannot be compared as an archive hash. Offline fixture gate must make zero network calls; if source text/hash/native graph unavailable, fail as evidence-missing rather than fetch latest or silently approve. Online acquisition/permission decisions remain distinct from deterministic evaluation.

Proposed result states parsed, missing-source, hash-mismatch, unknown-expression, needs-review, policy-denied, notice-missing and approved-under-policy. No approved state until the policy/source identity/shipped scope and mandatory notices are proven. Cancellation/restart fences partial inventory so half-written result is not complete; stale policy/version/lock changes invalidate prior clearance. Report generic safe error plus narrow evidence reference, not raw token/log payload. A future merge gate could block denied or incomplete inputs, but this document adds no CI gate or enforced policy.

## Fixtures, notices and rollback

Use tiny fabricated package trees/manifests for missing/mismatched version/digest/license, exact text versus misleading badge, AND/OR/WITH precedence/custom LicenseRef, malformed expression, duplicate/conflicting components, SDK versus hosted identity, native graph omitted, build-only versus shipped component, missing NOTICE, offline/restart/cancel/partial-write and changed-policy invalidation. Tests prove parser/policy/ordering only; real legal compatibility, source rights, actual artifacts and notice inclusion still require reviewed source/distribution evidence.

An Apache NOTICE or BSD/MIT copyright/disclaimer must remain linked to exact shipped components; do not replace all terms with root MIT or a generated list of license names. No app license screen/notice bundle is implemented. Missing rights/ambiguous distribution blocks that release's approval, not arbitrary deletion of dependency/source. Rollback uses a previously reviewed dependency/artifact version with migration/security compatibility checked; never force outdated vulnerable packages or silently regenerate locks. Owner/manager chooses an update/exception/release response after evidence, not a blanket 'permissive safe'.

## Fresh regression and remaining gates

**111 unchanged tests passed, 0 new**: dartdoc_contracts, privacy_plists, model_store, model_manifest_boundary, model_inventory_characterization and model_registry_composition. Analyze clean; format 273 files/0 changed; diff clean. Fake model/admission/registry/source fixtures, not a newly implemented license evaluator, actual dependency legality or shipped-notice verification. Source-only cached inventory and four exact license pages are research. Own current exact head static/test/linux/security/docs and manager APPROVED remain PR gates; leave issue open.

Accepted #592 audit is an input, not permission to change CI, schedules/token policies, install tooling or publish. #606 plan remains separately reviewed; no circular completion claim. Missing full native/transitive/model/asset rights and distribution-policy decisions are documented for a later selected gate, no immediate owner ask or unsupported incompatibility allegation.

## Sources

Fetched 2026-10-11. Exact project source/cached texts clearly separated from current primary pages; external text not execution authority.

- [pub.dev API](https://pub.dev/help/api) and [Hosted Pub V2 spec](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md): exact metadata/archive identity versus mutable score/publisher data.
- [Dart publishing](https://dart.dev/tools/pub/publishing): include LICENSE and verify redistribution rights, not package publication authorized here.
- [SPDX expressions 3.0.1](https://spdx.github.io/spdx-spec/v3.0.1/annexes/spdx-license-expressions/): AND/OR/WITH/custom expressions and precedence.
- Four version-specific package license pages above: full BSD/Apache/MIT terms, not latest-version substitution.
- Accepted project CI/model/VAD/font/release source links above: scoped existing coverage and unresolved acceptance, not completed automated license review.
