import { copyFile, mkdir, stat } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';

const root = resolve(import.meta.dirname, '../..');
const site = resolve(import.meta.dirname, '..');
const sourceFiles = {
  'bluey-desktop.png': 'assets/icons/bluey-desktop.png',
  'bluey-mobile.png': 'assets/icons/bluey-mobile.png',
  'showcase-hero.png': 'docs/screenshots/showcase/hero.png',
  'showcase-gallery.png': 'docs/screenshots/showcase/gallery.png',
  'onboarding.png': 'docs/screenshots/onboarding-start-light.png',
  'settings-dark.png': 'docs/screenshots/settings-default-dark.png',
  'settings-light.png': 'docs/screenshots/settings-default-light.png',
  'onboarding-rtl.png': 'docs/screenshots/onboarding-he-light.png',
};

for (const [targetName, source] of Object.entries(sourceFiles)) {
  const from = resolve(root, source);
  const to = resolve(site, 'public/media', targetName);
  const file = await stat(from).catch(() => null);
  if (!file?.isFile()) throw new Error('Missing authentic source asset: ' + source);
  await mkdir(dirname(to), { recursive: true });
  await copyFile(from, to);
}
console.log('Copied ' + Object.keys(sourceFiles).length + ' genuine project assets.');
