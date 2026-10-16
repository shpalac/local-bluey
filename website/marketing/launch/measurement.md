# Week 4 measurement and feedback scorecard

## Data collection boundaries

Tracking is **off by default**. If the owner has configured the approved Plausible site-specific script in the website's `PUBLIC_PLAUSIBLE_SCRIPT_URL` GitHub Actions variable, pages load it, and a delegated click listener reports only fixed event names:

| Event | Trigger | Interpretation |
| --- | --- | --- |
| `Setup Click` | Homepage setup GitHub CTAs | Interest in source setup, **not** a successful install |
| `GitHub Click` | Homepage or guide project-source CTA | Repository-navigation intent |
| `Guide Click` | Home resource or guide navigation | Information discovery |
| `Contribute Click` | Contribution-guide CTA | Contributor interest, **not** completed contribution |

No user-entered fields, link URLs, device identifiers, or free-text properties are attached to custom events. Plausible itself may still process standard pageview/referrer/UTM data; review its privacy disclosures and obtain any applicable consent before activation. Search Console verification alone does not activate visitor tracking.

The UTM builder outputs allowlisted links to the public GitHub Pages project. It does not perform telemetry or posting. `npm run test:gtm` enforces allowed routes, deterministic source attribution and rejection of arbitrary external URLs.

## Weekly review template

| Metric | Baseline | Current | Source | Notes |
| --- | --- | --- | --- | --- |
| Homepage views | unknown | — | Plausible when enabled | No baseline yet |
| Setup clicks | unknown | — | `Setup Click` | Clicks are not installs |
| Guide visits / clicks | unknown | — | Plausible when enabled | Compare topic intent |
| Qualified issues / discussions | unknown | — | GitHub public records | Manually classify |
| Real-device validations | unknown | — | #15 verification evidence | Required maturity gate |

If analytics is enabled, a descriptive funnel can report `Setup Click / homepage views`; do not interpret this as installer conversion or claim causal impact. Compare periods with similar promotion rather than presenting week-over-week changes as controlled experiments.

## Hypotheses and decisions

- If visitors read the Ollama page but do not navigate to setup, review the STT constraints and clarity before spending on distribution.
- If setup clicks rise without test reports, ask for opt-in reproducible device results; don't infer successful usage.
- If a community indicates promotion is unwelcome, stop posting there.
- If privacy disclosures are not ready, leave all analytics variables unset.

## Reporting cadence

At the end of each launch week, write a brief note: links shared (only with approval), qualitative reactions, test reports, broken links, any consent issues, and one next hypothesis. Do not fabricate numbers or ratings.
