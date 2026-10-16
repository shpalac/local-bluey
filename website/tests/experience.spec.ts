import { test, expect } from '@playwright/test';

test('hero, genuine screenshots, trust disclosures and navigation render', async ({ page }, testInfo) => {
  await page.goto('./');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('AI');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('sidekick');
  await expect(page.getByRole('link', { name: /Set up Bluey on Mac/i })).toHaveAttribute('href', /github.com\/shpalac\/local-bluey/);
  await expect(page.getByRole('link', { name: /See how it works/i })).toHaveAttribute('href', '#how');
  await expect(page.getByRole('link', { name: /Try the interactive approval demo/i })).toHaveAttribute('href', '#approval-demo');
  await expect(page.getByRole('heading', { name: 'macOS' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'iOS & Android' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Linux & Windows' })).toBeVisible();
  await expect(page.getByText(/not phone-control assistants/i)).toBeVisible();
  await expect(page.getByText(/End-to-end behavior on physical devices is not yet verified/i)).toBeVisible();
  await expect(page.getByText('Screenshots are deterministic')).toBeVisible();
  await expect(page.getByText(/Real-device validation is still pending/)).toBeVisible();
  const image = page.locator('img[alt*="Bluey"]').first();
  await expect(image).toBeVisible();
  expect(await image.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);
  const overflowing = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 2);
  expect(overflowing).toBe(false);
  // Capture actual on-scroll states rather than a misleading, never-scrolled
  // full-page image (ScrollTrigger deliberately reveals scenes as they enter).
  await page.screenshot({ path: testInfo.outputPath('hero.png'), animations: 'disabled' });
  const scenes = [
    ['meet', '#meet'],
    ['story', '#how'],
    ['control', '.control'],
    ['features', '.features'],
    ['platforms', '#platforms'],
    ['gallery', '#look'],
    ['privacy', '.privacy'],
    ['final', '.last-call']
  ] as const;

  for (const [name, selector] of scenes) {
    await page.locator(selector).scrollIntoViewIfNeeded();
    await page.waitForTimeout(300); // allow scrubbing and reveal animations to settle
    await page.screenshot({
      path: testInfo.outputPath(name + '.png'),
      animations: 'disabled'
    });
  }
  await page.screenshot({
    path: testInfo.outputPath('full-page-after-scroll.png'),
    fullPage: true,
    animations: 'disabled'
  });
});

test('walkthrough and navigation point to real sections, not decorative links', async ({ page }) => {
  await page.goto('./');
  const invalidAnchors = await page.locator('a[href^="#"]').evaluateAll((anchors) =>
    anchors.map((anchor) => anchor.getAttribute('href')?.slice(1) ?? '')
      .filter((id) => id !== '' && !document.getElementById(id))
  );
  expect(invalidAnchors).toEqual([]);

  const decorativeLabels = await page.locator('.story-step-footer, .feature-end, .gallery-mosaic figcaption').allTextContents();
  expect(decorativeLabels.every((text) => !text.includes('↗'))).toBe(true);
  await page.getByRole('link', { name: /Try the interactive approval demo/i }).click();
  await expect(page).toHaveURL(/#approval-demo$/);
  await expect(page.getByRole('button', { name: /Approve demo action/i })).toBeVisible();
});

test('approval illustration is interactive without claiming to perform real actions', async ({ page }) => {
  await page.goto('./');
  await page.getByRole('button', { name: /Approve demo action/i }).click();
  await expect(page.getByText('Approved — demo only')).toBeVisible();
  await page.getByRole('button', { name: /Reset demo/i }).click();
  await expect(page.getByText('Awaiting your approval')).toBeVisible();
});

test('reduced motion retains information and avoids scroll pinning', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('./');
  await expect(page.getByRole('heading', { name: /Your Mac.*Your rules/i })).toBeVisible();
  await expect(page.locator('.story-step')).toHaveCount(4);
});


test('SEO metadata, structured data and the sitemap describe the actual Mac host', async ({ page, request }) => {
  await page.goto('./');

  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://shpalac.github.io/local-bluey/');
  await expect(page.locator('meta[property="og:url"]')).toHaveAttribute('content', 'https://shpalac.github.io/local-bluey/');
  await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute('content', 'summary_large_image');
  await expect(page.locator('meta[name="twitter:image"]')).toHaveAttribute('content', /https:\/\/shpalac\.github\.io\/local-bluey\/media\//);
  await expect(page.locator('link[rel="sitemap"]')).toHaveAttribute('href', 'https://shpalac.github.io/local-bluey/sitemap-index.xml');

  const jsonLd = await page.locator('script[type="application/ld+json"]').textContent();
  expect(jsonLd).toBeTruthy();
  const app = JSON.parse(jsonLd!);
  expect(app['@type']).toBe('SoftwareApplication');
  expect(app.operatingSystem).toBe('macOS');
  expect(app.offers.price).toBe(0);
  expect(app.aggregateRating).toBeUndefined();
  expect(app.downloadUrl).toBeUndefined();

  const sitemapIndex = await request.get('./sitemap-index.xml');
  expect(sitemapIndex.ok()).toBe(true);
  expect(await sitemapIndex.text()).toContain('https://shpalac.github.io/local-bluey/sitemap-0.xml');
  const sitemap = await request.get('./sitemap-0.xml');
  expect(sitemap.ok()).toBe(true);
  expect(await sitemap.text()).toContain('<loc>https://shpalac.github.io/local-bluey/</loc>');
});

test('verification and analytics are absent unless configured', async ({ page }) => {
  await page.goto('./');
  if (!process.env.PUBLIC_GOOGLE_SITE_VERIFICATION) {
    await expect(page.locator('meta[name="google-site-verification"]')).toHaveCount(0);
  }
  if (!process.env.PUBLIC_PLAUSIBLE_SCRIPT_URL) {
    await expect(page.locator('script[src^="https://plausible.io/js/pa-"]')).toHaveCount(0);
  }
});

test('source-backed guides are discoverable, navigable and honest about validation', async ({ page, request }) => {
  await page.goto('./');
  const guides = [
    ['guides/mac-setup/', 'Set up Local Bluey on Mac'],
    ['guides/ollama/', 'Using Ollama with Local Bluey'],
    ['features/screen-understanding/', 'Understand your Mac screen with Bluey'],
    ['features/approval-safety/', 'Computer actions stay under your approval']
  ] as const;
  await expect(page.locator('#resources .resource-card')).toHaveCount(4);
  await expect(page.locator('#resources details')).toHaveCount(4);
  for (const [route, title] of guides) {
    await expect(page.locator('#resources a[href$="' + route + '"]')).toHaveCount(1);
    const response = await request.get('./' + route);
    expect(response.ok()).toBe(true);
    const html = await response.text();
    expect(html).toContain('real-device verification is still pending');
    expect(html).toContain('href="https://shpalac.github.io/local-bluey/' + route + '"');
    await page.goto('./' + route);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText(title);
    await expect(page.getByRole('navigation', { name: 'Guide navigation' }).getByRole('link', { name: 'All guides' })).toHaveAttribute('href', '/local-bluey/#resources');
    await page.goto('/local-bluey/');
  }
});

test('launch conversion links have only allowlisted event names and no default tracking', async ({ page }) => {
  await page.goto('./');
  const labels = await page.locator('a[data-gtm-event]').evaluateAll((links) =>
    links.map((link) => link.getAttribute('data-gtm-event'))
  );
  for (const name of ['Setup Click', 'GitHub Click', 'Guide Click', 'Contribute Click']) {
    expect(labels).toContain(name);
  }
  expect(labels.every((name) => ['Setup Click', 'GitHub Click', 'Guide Click', 'Contribute Click'].includes(name ?? ''))).toBe(true);
  if (!process.env.PUBLIC_PLAUSIBLE_SCRIPT_URL) {
    await expect(page.locator('script[src^="https://plausible.io/js/pa-"]')).toHaveCount(0);
    await page.goto('/local-bluey/guides/mac-setup/');
    await expect(page.locator('script[src^="https://plausible.io/js/pa-"]')).toHaveCount(0);
  }
});

test('preview CTAs use only fixed event names without default analytics', async ({ page }) => {
  await page.goto('./');
  const names = await page.locator('a[data-gtm-event]').evaluateAll((nodes) =>
    nodes.map((node) => node.getAttribute('data-gtm-event'))
  );
  const allowed = ['Setup Click', 'GitHub Click', 'Guide Click', 'Contribute Click'];
  for (const name of allowed) expect(names).toContain(name);
  expect(names.every((name) => allowed.includes(name ?? ''))).toBe(true);
  if (!process.env.PUBLIC_PLAUSIBLE_SCRIPT_URL) {
    await expect(page.locator('script[src^="https://plausible.io/js/pa-"]')).toHaveCount(0);
    await page.goto('/local-bluey/guides/mac-setup/');
    await expect(page.locator('script[src^="https://plausible.io/js/pa-"]')).toHaveCount(0);
  }
});
