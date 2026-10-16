import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

// Fixed host and allowlisted routes prevent accidentally distributing
// tracking links to unreviewed domains or internal/private URLs.
export const SITE_URL = 'https://shpalac.github.io/local-bluey/';
export const CAMPAIGN = 'developer_preview_2026';
export const CHANNELS = Object.freeze({
  hackernews: 'hackernews',
  reddit: 'reddit',
  devto: 'devto',
  github: 'github'
});
export const DESTINATIONS = Object.freeze({
  home: '',
  macSetup: 'guides/mac-setup/',
  ollama: 'guides/ollama/',
  screen: 'features/screen-understanding/',
  safety: 'features/approval-safety/'
});

export function buildCampaignUrl(channel, destination = 'home') {
  if (!Object.hasOwn(CHANNELS, channel)) throw new RangeError('Unknown launch channel: ' + String(channel));
  if (!Object.hasOwn(DESTINATIONS, destination)) throw new RangeError('Unknown destination: ' + String(destination));
  const url = new URL(DESTINATIONS[destination], SITE_URL);
  url.searchParams.set('utm_source', CHANNELS[channel]);
  url.searchParams.set('utm_medium', 'community');
  url.searchParams.set('utm_campaign', CAMPAIGN);
  return url.toString();
}

export function formatCampaignLinks() {
  return Object.keys(CHANNELS).map((channel) =>
    channel + ': ' + buildCampaignUrl(channel) + '\n' +
    '  Mac setup: ' + buildCampaignUrl(channel, 'macSetup') + '\n' +
    '  Ollama guide: ' + buildCampaignUrl(channel, 'ollama')
  ).join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.stdout.write(formatCampaignLinks() + '\n');
}
