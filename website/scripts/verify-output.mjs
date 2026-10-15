import { readFile, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

const root = resolve(import.meta.dirname, '..');
const read = async (p) => readFile(resolve(root, 'dist', p), 'utf8');
const html = await read('index.html');

for (const phrase of [
  'Local Bluey', 'HAS AN AI', 'Set up Bluey on Mac',
  'HOW BLUEY HELPS', 'Screenshots are deterministic',
  'YOUR MAC. YOUR RULES.', 'WHAT BLUEY CAN DO',
  'PHONE COMPANIONS', 'Linux has experimental host backends'
]) {
  assert.ok(html.includes(phrase), 'Missing meaningful page content: ' + phrase);
}
assert.ok(html.includes('/local-bluey/'), 'Broken GitHub Pages subpath');
assert.ok(html.includes('href="#approval-demo"') && html.includes('id="approval-demo"'), 'Broken demo anchor');
assert.ok(html.includes('href="#platforms"') && html.includes('id="platforms"'), 'Broken platform navigation');
assert.ok(html.includes('Real-device validation is still pending'), 'Missing physical-device disclosure');
assert.ok(!html.includes('Download for macOS'), 'Do not advertise unverified release downloads');

// SEO must reference the GitHub Pages project URL, not the github.io domain root.
const canonicalUrl = 'https://shpalac.github.io/local-bluey/';
const sitemapUrl = canonicalUrl + 'sitemap-index.xml';
assert.ok(html.includes('rel="canonical" href="' + canonicalUrl + '"'), 'Incorrect canonical URL');
assert.ok(html.includes('rel="sitemap" type="application/xml" href="' + sitemapUrl + '"'), 'Missing sitemap discovery link');
for (const attribute of ['og:url', 'og:image', 'og:image:alt', 'twitter:card', 'twitter:title', 'twitter:description', 'twitter:image', 'twitter:image:alt']) {
  const kind = attribute.startsWith('og:') ? 'property' : 'name';
  assert.ok(html.includes(kind + '="' + attribute + '"'), 'Missing social metadata: ' + attribute);
}
assert.match(html, /name="twitter:card" content="summary_large_image"/);

const jsonLdBlocks = [...html.matchAll(/<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/g)];
assert.equal(jsonLdBlocks.length, 1, 'Expected exactly one SoftwareApplication schema block');
const app = JSON.parse(jsonLdBlocks[0][1]);
assert.equal(app['@context'], 'https://schema.org');
assert.equal(app['@type'], 'SoftwareApplication');
assert.equal(app.name, 'Local Bluey');
assert.equal(app.url, canonicalUrl);
assert.equal(app.operatingSystem, 'macOS');
assert.equal(app.applicationCategory, 'DesktopEnhancementApplication');
assert.equal(app.isAccessibleForFree, true);
assert.equal(app.offers.price, 0);
assert.ok(app.codeRepository.endsWith('/shpalac/local-bluey'));
for (const inventedClaim of ['aggregateRating', 'review', 'downloadUrl', 'installUrl']) {
  assert.ok(!(inventedClaim in app), 'Unverified schema claim: ' + inventedClaim);
}
if (!process.env.PUBLIC_GOOGLE_SITE_VERIFICATION) {
  assert.ok(!html.includes('name="google-site-verification"'), 'Verification requires an account token');
}
if (!process.env.PUBLIC_PLAUSIBLE_SCRIPT_URL) {
  assert.ok(!html.includes('https://plausible.io/js/pa-'), 'Analytics must be opt-in');
}

const sitemapIndex = await read('sitemap-index.xml');
const pageSitemap = await read('sitemap-0.xml');
assert.ok(sitemapIndex.includes('https://shpalac.github.io/local-bluey/sitemap-0.xml'), 'Incorrect sitemap index URL');
assert.ok(pageSitemap.includes('<loc>' + canonicalUrl + '</loc>'), 'Missing canonical page from sitemap');
const newPages = [
  ['guides/mac-setup', 'Set up Local Bluey on Mac'],
  ['guides/ollama', 'Using Ollama with Local Bluey'],
  ['features/screen-understanding', 'Understand your Mac screen with Bluey'],
  ['features/approval-safety', 'Computer actions stay under your approval']
];
for (const [route, title] of newPages) {
  const expectedUrl = canonicalUrl + route + '/';
  const guideHtml = await read(route + '/index.html');
  assert.ok(guideHtml.includes('<h1>' + title + '</h1>'), 'Missing guide heading: ' + route);
  assert.ok(guideHtml.includes('rel="canonical" href="' + expectedUrl + '"'), 'Incorrect canonical: ' + route);
  assert.ok(guideHtml.includes('real-device verification is still pending'), 'Missing maturity disclaimer: ' + route);
  assert.ok(pageSitemap.includes('<loc>' + expectedUrl + '</loc>'), 'Missing sitemap location: ' + route);
  assert.ok(html.includes('href="/local-bluey/' + route + '/"'), 'Missing home link: ' + route);
}
assert.ok(html.includes('id="resources"') && html.includes('id="faq-title"'), 'Missing resources FAQ');
for (const name of ['Setup Click', 'GitHub Click', 'Guide Click', 'Contribute Click']) {
  assert.ok(html.includes('data-gtm-event="' + name + '"'), 'Missing CTA event: ' + name);
}
if (!process.env.PUBLIC_PLAUSIBLE_SCRIPT_URL) {
  for (const route of ['guides/mac-setup/index.html', 'guides/ollama/index.html']) {
    assert.ok(!(await read(route)).includes('plausible.io/js/pa-'), 'Guide unexpectedly enables analytics: ' + route);
  }
}
const eventNames = ['Setup Click', 'GitHub Click', 'Guide Click', 'Contribute Click'];
for (const name of eventNames) {
  assert.ok(html.includes('data-gtm-event="' + name + '"'), 'Missing conversion event link: ' + name);
}
if (!process.env.PUBLIC_PLAUSIBLE_SCRIPT_URL) {
  for (const file of ['guides/mac-setup/index.html', 'guides/ollama/index.html']) {
    assert.ok(!(await read(file)).includes('plausible.io/js/pa-'), 'Guide unexpectedly injects analytics: ' + file);
  }
}
for (const name of ['bluey-desktop.png', 'showcase-gallery.png', 'settings-dark.png']) {
  assert.ok((await stat(resolve(root, 'dist/media', name))).size > 1000, 'Missing authentic image: ' + name);
}
console.log('Static output and truthful claims verified.');
