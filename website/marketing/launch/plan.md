# Local Bluey — developer-preview GTM plan

Status: **draft for approval; no community posts have been published**. The product has source-level features and CI coverage, but physical-device validation is pending ([issue #15](https://github.com/shpalac/local-bluey/issues/15)). Do not market this as a production-ready assistant or a verified Mac download.

## Positioning and audience

**One-line pitch:** Local Bluey is an open-source, playful Mac AI companion that can inspect your screen and propose computer actions behind an explicit approval gate.

Focus on three early audiences:

1. **Flutter/macOS contributors:** Help validate native permissions and host behavior.
2. **Local AI builders:** Try or inspect the Ollama integration and report gaps, particularly speech configuration.
3. **Mac productivity experimenters:** Explore the concept and contribute reproducible feedback; do not expect consumer reliability.

Avoid outbound cold email. Make opt-in, useful community contributions rather than unsolicited promotion.

## Launch readiness checkpoints

Before posting in a new community:
- Confirm the live website, documentation links, and sitemap are deployed.
- Run GitHub-hosted website CI plus manually verify one actual Mac session when possible.
- If #15 remains open, lead with **developer preview / seeking testers** rather than a working release.
- Clearly label any illustration or screenshot as a deterministic capture, not a real-device recording.
- Review current community rules and disclose your affiliation.

## Four controlled distribution experiments

| Channel | Helpful opening | Landing route | Primary outcome |
| --- | --- | --- | --- |
| GitHub Discussions / repo README | Architecture + validation checklist | Mac setup guide | Qualified testing reports |
| Relevant Flutter or open-source groups | How the Flutter macOS host is structured | Mac setup guide | Contributor questions |
| Local AI communities (only when rules permit) | Ollama-as-brain, separate STT caveats | Ollama guide | Guide visits, specific feedback |
| Hacker News / developer blogs (when ready) | Build log and lessons, not a product launch claim | Homepage | Constructive project feedback |

Test one angle per channel; do not post identical promotional text everywhere. No fake adoption claims, comparisons without evidence, or purchased votes.

## Week-by-week experiment loop

1. **Prepare:** use `npm run gtm:links` to generate deterministic, allowlisted UTM links.
2. **Review:** verify screenshots and facts against the current support matrix.
3. **Publish manually only with approval:** use the copy in `launch-copy.md` and update it to comply with each community's rules.
4. **Measure:** when Plausible is deliberately enabled, observe anonymized pageviews and named CTA events. Without it, rely on GitHub discussions, issues, and qualitative feedback.
5. **Learn:** log audience, hypothesis, post URL, date, relevant responses, defects, and next action. Stop ineffective or unwelcome promotion.

See `measurement.md` for event definitions and the weekly scorecard.
