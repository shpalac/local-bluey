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
for (const name of ['bluey-desktop.png', 'showcase-gallery.png', 'settings-dark.png']) {
  assert.ok((await stat(resolve(root, 'dist/media', name))).size > 1000, 'Missing authentic image: ' + name);
}
console.log('Static output and truthful claims verified.');
