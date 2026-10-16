import test from 'node:test';
import assert from 'node:assert/strict';
import { SITE_URL, CAMPAIGN, CHANNELS, DESTINATIONS, buildCampaignUrl, formatCampaignLinks } from './gtm-links.mjs';

test('only approved launch channels and site routes can produce share URLs', () => {
  for (const channel of Object.keys(CHANNELS)) {
    for (const destination of Object.keys(DESTINATIONS)) {
      const first = buildCampaignUrl(channel, destination);
      assert.equal(first, buildCampaignUrl(channel, destination), 'Links must be deterministic');
      const parsed = new URL(first);
      assert.equal(parsed.origin, 'https://shpalac.github.io');
      assert.ok(parsed.pathname.startsWith('/local-bluey/'));
      assert.equal(parsed.searchParams.get('utm_source'), channel);
      assert.equal(parsed.searchParams.get('utm_medium'), 'community');
      assert.equal(parsed.searchParams.get('utm_campaign'), CAMPAIGN);
      assert.deepEqual([...parsed.searchParams.keys()], ['utm_source', 'utm_medium', 'utm_campaign']);
      assert.ok(first.startsWith(SITE_URL));
    }
  }
});

test('rejects unapproved channels, routes and external redirects', () => {
  for (const [channel, destination] of [
    ['../private', 'home'], ['unknown', 'home'], ['hackernews', '../private'],
    ['reddit', 'https://another.example/'], ['constructor', 'home'],
    ['github', '__proto__']
  ]) {
    assert.throws(() => buildCampaignUrl(channel, destination), RangeError);
  }
});

test('published copy can reuse a reviewed source of deterministic campaign links', () => {
  const output = formatCampaignLinks();
  assert.ok(output.includes('hackernews:'));
  assert.ok(output.includes('Mac setup:'));
  assert.ok(output.includes('Ollama guide:'));
  assert.ok(!output.includes('undefined'));
});
