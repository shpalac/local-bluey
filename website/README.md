# Local Bluey — cinematic product site

A handcrafted, static Astro + React site (Tailwind via PostCSS for Astro 6 compatibility) using the project's real Bluey icon and deterministic Flutter screenshots.

## Development

From the repository root:

```sh
cd website
npm install
npm run dev
```

The site is served at http://localhost:4321/local-bluey/. `predev` and `prebuild` copy the *existing repository assets* into `public/media`. Do not add generated replacement screenshots or claim device testing.

```sh
npm run check
npm run build
npm run test:static
npx playwright install chromium
npm run test:visual
npm run test:lighthouse
```

## Search visibility and privacy-conscious analytics

The site generates `sitemap-index.xml` and `sitemap-0.xml` via the official Astro sitemap integration. URLs must include the GitHub Pages project path:

- Canonical homepage: `https://shpalac.github.io/local-bluey/`
- Sitemap to submit: `https://shpalac.github.io/local-bluey/sitemap-index.xml`

Google Search Console setup (requires the repository/site owner's Google account):

1. Add a **URL-prefix property** for `https://shpalac.github.io/local-bluey/` in Search Console.
2. Copy the HTML verification tag's `content` value (not the whole tag).
3. Set `PUBLIC_GOOGLE_SITE_VERIFICATION` as a GitHub Actions **variable** for the website build, then rebuild/deploy. The output contains the meta tag only when this value is present.
4. After deployment, verify site ownership in Search Console and submit `sitemap-index.xml`.
5. Monitor Search Console indexing, queries and click-through rate. Verification and submission require the owner's action and are **not performed by CI**.

Example for a local preview:

```sh
PUBLIC_GOOGLE_SITE_VERIFICATION="your-verification-content" npm run build
```

**Privacy-conscious analytics are disabled by default.** To opt into Plausible:

1. Create a site in Plausible for the appropriate GitHub Pages domain/path and review its data collection settings and disclosure requirements.
2. Copy the **site-specific HTTPS script URL** (`https://plausible.io/js/pa-XXXXX.js`) from its installation settings.
3. Supply it as the build variable `PUBLIC_PLAUSIBLE_SCRIPT_URL` in the website workflow when deliberately enabling analytics. Other script origins and legacy script paths are rejected during build.
4. Confirm that the script and data collection work as expected, and update the site's public privacy documentation before enabling tracking.

No Google Analytics, ad trackers, cookies or external analytics scripts are injected when those variables are unset. A Search Console verification meta tag by itself does not track visitors.

**GitHub Pages limitation:** Project Pages sites do not control the domain-root `/robots.txt`, so placing a robots file under `/local-bluey/` would not enforce host-wide crawler rules. We rely on the project sitemap and Search Console instead; do not describe a project-path robots file as controlling indexing.

Structured data describes the source-available macOS host and a free project setup, not a verified downloadable release. Ratings, reviews and download links are intentionally omitted until proven.

## Motion system

- **GSAP + ScrollTrigger:** cinematic reveals, pinned horizontal narrative on larger screens, and progressive captions.
- **React Three Fiber + Three.js:** decorative WebGL atmosphere behind the original mascot artwork; WebGL is not a replacement Bluey model.
- **Motion:** the interactive approval illustration with spring feedback, explicitly labeled as a demo.
- **Rive:** optional real character state-machine integration. No `.riv` character asset exists in the repository. To activate it, supply a licensed, character-matched Rive file in `public/` and set `PUBLIC_BLUEY_RIVE_URL` at build time. Its state machine must be named `Bluey` with a Boolean input `hover`. Without it, the authentic mascot icon remains visible. Do not publish a fabricated Rive animation.

Effects respect `prefers-reduced-motion`. The WebGL island mounts only with WebGL support, capable hardware and non-reduced motion, and is never needed to consume content.

## Deployment

The isolated `.github/workflows/website.yml` runs only on relevant website/artwork changes, checks the page, collects Chromium screenshots, audits Lighthouse scores and builds a Pages artifact. On `main`, it deploys to https://shpalac.github.io/local-bluey/.

**One-time repository owner setup:** Settings → Pages → Build and deployment → Source: **GitHub Actions**. The connector cannot perform this administrative setting. Deployment will not be live until that is enabled and a successful `main` run completes.

This website does not claim an app-store release, verified native device support, guaranteed local-only processing, or guaranteed secret redaction.

## Visual principles

Make Bluey the star. Cream editorial type against ink-violet, vivid blueberry and citron accents; playful orbit marks and deliberately asymmetric layouts; small motion where it adds delight, scroll narrative only where it tells the real product story. Avoid stock illustrations, generic SaaS feature-card grids, overpromised AI magic, and invented UI.

## Source-backed feature guides

The four Week 3 Astro pages are accessible from the homepage resources section and generated sitemap:
`guides/mac-setup/`, `guides/ollama/`, `features/screen-understanding/` and `features/approval-safety/`.

The shared `src/layouts/GuideLayout.astro` provides canonical URLs, accessible navigation and a consistent status disclaimer. These guides document source-level functionality and limitations; they do not claim real-device validation.
