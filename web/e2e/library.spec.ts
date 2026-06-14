import { test, expect } from '@playwright/test';

// Mock backend responses so E2E runs without a live server
test.beforeEach(async ({ page }) => {
  await page.route('**/albums', route =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        {
          id: 'super-mario-rpg',
          title: 'Super Mario RPG: Legend of the Seven Stars',
          platform: 'SNES', year: 1996, albumType: 'OST',
          trackCount: 42, coverUrls: [],
        },
        {
          id: 'chrono-trigger',
          title: 'Chrono Trigger Original Sound Version',
          platform: 'SNES', year: 1995, albumType: 'OST',
          trackCount: 65, coverUrls: [],
        },
      ]),
    })
  );
  await page.route('**/history**', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: '[]' })
  );
});

test('library page loads and shows albums', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('Super Mario RPG')).toBeVisible();
  await expect(page.getByText('Chrono Trigger Original Sound Version')).toBeVisible();
});

test('library shows album platform and year', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('SNES').first()).toBeVisible();
  await expect(page.getByText('1996').first()).toBeVisible();
});

test('library sidebar navigation links exist', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: /library/i }).first()).toBeVisible();
});

test('player bar is present', async ({ page }) => {
  await page.goto('/');
  // Player bar exists but no track loaded
  await expect(page.locator('.player-bar, [class*="player"]').first()).toBeVisible();
});
