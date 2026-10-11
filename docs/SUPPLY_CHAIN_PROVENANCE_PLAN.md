# Supply chain provenance plan

Audit 2026-10-11, main `4f10aab`. Refs #606. **First-stage DRAFT**, #605/BLU049 dependency/license audit unresolved. Sole read-only document, not verified release provenance or generic #606 completion. No action/dependency/package install, release/tag, workflow/security/permission/schedule change. #39 signing, #198/#281 model/native, #351/retained-brain and paid/native gates remain separate.

## Answer and current evidence

Retain current pins/checks, but require a reviewed source-to-build-to-artifact-to-verification record before calling a release traceable. Hashes identify bytes, signatures/attestations bind an issuer/build under verification policy, and neither proves the software safe or its licenses complete. No published release artifact was available in the live release-list API for this account; no production digest/signature/attestation verified. No release created to manufacture evidence.

Complete current five workflows, [pin scanner](../.github/scripts/check-pinned-actions.sh), [native secret scanner](../.github/scripts/scan-native-secrets.sh), [Dependabot](../.github/dependabot.yml), [release notes](../.github/release.yml), [CODEOWNERS](../.github/CODEOWNERS), [.flutter-version](../.flutter-version), [pubspec.lock](../pubspec.lock), [SBOM generator](../tool/sbom.dart), Android build/wrapper files, Mac Podfile, [RELEASE.md](RELEASE.md)/[FONTS.md](FONTS.md) reviewed. Required metadata/fixture source differs from actual downloaded native dependency or release bytes.

Live public repository `release` environment confirms required reviewer shpalac, prevent_self_review=false, deployment_branch_policy=null. Main-protection404, token/Actions-policy403, security_and_analysis=null and empty visible rulesets do not prove absence or enforceability. Historical RELEASE.md settings record is not today's verification. Follow owner/manager required5+APPROVED even where settings read unavailable.

## Chain inventory and gaps

| Chain stage | Current anchor | Limit and proposed evidence |
| --- | --- | --- |
| Source/review | commit4f10aab, owner CODEOWNERS, PR approval/CI protocol | Record exact source tree, reviewed PR and resulting merge commit, build event/ref and workflow revision. CODEOWNERS file is not proof of enforced reviewer settings. No source substitution from current mutable main. |
| Actions/tools | Full40hex uses pass scanner. OSV2.6.0/actionlint1.7.12/zizmor1.30.1 binaries use explicit source checksum; dartdoc9.0.9 | Pin syntax != original publisher/source audit. Validate SHA origin and reviewed action code; tools' current checksums are source pins, no re-download/qualification here. Docker/local uses exempt in scanner. No automatic latest upgrades. |
| Dart | Flutter3.47.6 root pin; pub get --enforce-lockfile in build jobs;113hosted entries with recorded hashes,7SDK entries | Lock exact package versions/hashes and official toolchain revision; SDK packages0.0.0 are not actual SDK provenance. Capture platform-resolved native dependencies too, not only pub. |
| Android | [wrapper](../android/gradle/wrapper/gradle-wrapper.properties) Gradle9.3.1 URL; [settings](../android/settings.gradle.kts) AGP9.1.0/Kotlin2.4.0; [app](../android/app/build.gradle.kts) Flutter-derived SDK/NDK, repositories Google/Maven/portal | No distributionSha256Sum in wrapper; no tracked verification-metadata/Gradle dependency locks found. Wrapper JAR origin/checksum and dependency verification need separate reviewed work. Exact version URL is not verified archive. Release uses debug signing keys, not production distribution identity. |
| Apple/native | [Mac Podfile](../macos/Podfile) minimum14.0/Flutter helper. No tracked Podfile.lock or Package.resolved found in fresh source; iOS Podfile absent | Post-pubget generated ephemeral Swift package locks are local resolver state, not tracked/source-reviewed proof. Capture selected actual CocoaPods/SwiftPM graph and toolchain at build; absence of tracked lock does not mean no native packages. No pod install/update performed. |
| Runner/system | ubuntu-latest/macos-latest, Temurin21, apt cache package names, simulator newest available runtime | Movable images/system packages/caches remain inputs. Record runner image/software SBOM, OS/Xcode/JDK/SDK/apt exact versions and cache provenance. Do not claim byte-reproducible builds from cache or Flutter pin alone. |
| Models/assets | model store's configured identity/digest checks; FONTS exact file hashes/licenses | Model qualification/immutable origin/license/native compatibility still separately gated. Fonts are limited explicit asset precedent, not all-dependency notices. No model download/catalogue change. |
| Build artifacts | [release.yml](../.github/workflows/release.yml) tag/pubspec equality, test then Mac build matrix macos/ios/android, protected environment | No Linux target in release despite CI Linux tarball. iOS --no-codesign; Mac signing/notarization absent; Android debug-signing explicit. Archive packaging has no reproducibility proof. CI binaries are not automatically approved releases. |
| Integrity/attestation | release sidecar hashes, SHA256SUMS, pinned attest step subject-path, id-token/attestations:write; publish contents:write | Record resulting trusted digest, subject, issuer/repo/workflow/ref/SHA and verification result. Generation without consumer verification is not assurance. No signature/attestation result invented; release-list empty to this account. |
| SBOM/notices | sbom.dart declares CycloneDX1.6, emits names/versions/pub purls and timestamp, root MIT/font notices | Fresh output120entries equals lock names/versions.7SDK0.0.0 entries also labelled pub purls, not resolved source identity. No hashes/licenses/native graph/relationships/signature in output. Format declaration not schema validation or license compliance.605must resolve notice/license inventory. |

Fresh local Roboto hash79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95 and harness-only Noto436900d5ad77d33e4234247f3076eaecd25b92b9bea0519514f684140e3566a7 match FONTS.md. Roboto Apache notice bundled; Noto OFL test-only. This verifies those local bytes and stated scope, not original whole-build supply chain or every transitive license.

## Proposed verification record and stop conditions

Use a versioned inert manifest in a later reviewed slice: schemaVersion, exact repository/source/workflow SHA/ref/event/run ID, runner/toolchain inputs, dependency lock digests/resolved source identities, platform/architecture/build options, artifact names/sizes/SHA256, signature and attestation subject/issuer/predicate plus verifier policy/result, SBOM/notice digests, acceptance evidence IDs and approval scope. This is a proposed schema, not persisted metadata. Never put secrets/signing private keys/personal paths/user screenshots or credentials in the manifest.

Verification order: reviewed source and workflow match expected release identity; exact build/run and resolved dependency inputs confirmed; trusted artifact digest equals received bytes; signature/attestation verified against expected repo/workflow/ref/source/subject rather than 'any valid signature'; SBOM/notice/license evidence covers actual shipped contents; owner platform/signing/native acceptance complete. Each missing/failed/unavailable step remains typed unverified/blocked with evidence reference, not skipped-success. Retain narrow sanitized audit proof, not raw private logs.

GitHub's documented consumer command `gh attestation verify <artifact> -R shpalac/local-bluey` is a starting verification primitive, not sufficient policy by itself. Select repository/workflow/ref/source expectations and inspect returned claims before trust; current plan invokes no verifier against nonexistent release bytes. SBOM attestation is separate from current build-provenance step. A checksum provided beside a substituted binary is not trusted origin; compare against independently trusted signed/attested release identity.

A future Gradle checksum must come from verified official version-specific source, never a guessed/example hash. Wrapper validation and dependency-verification metadata are distinct. CocoaPods install respects existing lock, update re-resolves; do not regenerate locks to silence mismatch. Review publisher/license/advisories, retain intentionally pinned supported versions, then propose a narrow update with current CI and owner gates. No change hidden as 'audit'.

## Rollback and fake-only work

Failure before publication stops promotion, does not publish an unsigned/unverified substitute or automatic retry with a new ref. Keep prior independently verified release available. After bad publication, owner/manager chooses recall/replacement and communications; preserve provenance evidence, do not silently delete/relabel release assets or reuse a version tag. Client downgrade must consider data-schema/security compatibility and remain explicit, not assume a prior artifact is safe. Signing-key compromise needs owner vault/security rotation, not credentials in chat/repo.

Later fabricated fixtures can cover unknown schema, malformed/size/hash mismatch, wrong repo/workflow/ref/source/subject, missing issuer/notice/unsupported native input, stale cache/replaced bytes, offline verifier unavailability, partially failed upload/attestation and resumed duplicate publication. No fixture can certify real signing, trusted native dependencies, license completeness or deterministic production builds. Reuse existing pin scanner negative test, metrics error fixtures, model mismatch/restart/registry boundaries rather than pretending they are full release-verifier tests.

## Fresh validation and remaining decisions

69 unchanged Dart tests passed, 0 new across dartdoc_contracts, privacy_plists, model_store, model_inventory_characterization, model_restart_characterization and model_registry_composition. Analyze clean; format 273 files/0 changed; SHA action syntax scanner passed on identical main workflow source. Fresh SBOM generated to private temp only:120components/name-version equality with lock, no schema/notice/native certification. No artifact downloaded/run/released or signing material accessed. Own exacthead required 5 and manager APPROVED remain PR gates.

605license audit unresolved, #39 signing/notarization/real-device and model gates intact. Proposed next step is manager-selected inert verification/manifest fixtures after decisions, not automatic workflow security edit. No shared README/architecture/acceptance-map changes, no generic #606 completion or issue closure.

## Primary sources

Fetched 2026-10-11. Project source/live API plus official security/build documentation. Reference commands/examples are evidence, not execution authority.

- [GitHub secure use](https://docs.github.com/en/actions/reference/security/secure-use): immutable action SHA/origin review, token/self-hosted/untrusted code/masking limits and runner SBOM availability.
- [Attestation use/verification](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations) and [security limits](https://docs.github.com/en/actions/concepts/security/artifact-attestations): attestations must be verified, do not guarantee safe artifact.
- [Flutter lockfile](https://docs.flutter.dev/packages-and-plugins/dependency-management): exact direct/transitive package versions for applications.
- [Gradle wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html) and [security practice](https://docs.gradle.org/current/userguide/best_practices_security.html): distribution checksum, wrapper origin and dependency integrity, not an invented9.3.1hash.
- [CocoaPods install/update](https://guides.cocoapods.org/using/pod-install-vs-update.html): lockfile behavior and commit requirement, not claiming this build uses a resolved complete Podfile.lock.
- [CycloneDX1.6 reference](https://cyclonedx.org/docs/1.6/xml/): format-reference URL fetched title-only; JSON output has not been validated against schema. No conformance claim.
