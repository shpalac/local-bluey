# Security policy

## Supported versions

Bluey is pre-release: only `main` is supported. There are no stable
releases yet; fixes land on `main` and are not backported.

## Reporting a vulnerability

Bluey is a computer-use agent: it captures the screen, injects input and
runs tools against the host. A vulnerability here can mean someone else
driving your machine, so please report privately.

- Email: open a private report through GitHub's
  [private vulnerability reporting](../../security/advisories/new)
  for this repository. Do not open a public issue for a live
  vulnerability.
- If advisory creation is unavailable, open an issue titled
  "security report - please contact" with no details and ask for a
  private channel.

Please include the affected platform (macOS host, iOS/Android companion,
link layer), a description of the trust boundary crossed (pairing, HMAC,
allowlist, privacy redaction), and a repro or packet capture if you have
one. We acknowledge within 72 hours.

## Scope notes

- The phone-to-host link is HMAC-authenticated with per-pairing keys
  (#111); pairing approval and revocation are user actions (#112).
- The privacy guard redacts sensitive screen content before it leaves
  the host (#122); local-only mode blocks cloud transcription/TTS (#120).
- CI runs gitleaks (secrets) and a pinned, checksum-verified OSV scan on
  every push and weekly (#144).
