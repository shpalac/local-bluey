import { test, expect } from '@playwright/test';

test('hero, genuine screenshots, trust disclosures and navigation render', async ({ page }, testInfo) => {
  await page.goto('./');
  await expect(page.getByRole('heading', { level: 1 })).toContainText('sidekick');
  await expect(page.getByRole('link', { name: /Get started/i }).first()).toHaveAttribute('href', /github.com\/shpalac\/local-bluey/);
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
