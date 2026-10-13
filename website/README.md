# Local Bluey — cinematic product site

A handcrafted, static Astro + React site using the project's real Bluey icon and deterministic Flutter screenshots.

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
