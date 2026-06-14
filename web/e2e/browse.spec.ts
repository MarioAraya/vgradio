import { test, expect } from '@playwright/test';

const mockCatalogPage = (items = [] as object[]) => ({
  total: items.length, offset: 0, limit: 50, items,
});

const sampleEntries = [
  { title: 'Tekken 5 Original Soundtrack', sourceUrl: 'https://downloads.khinsider.com/game-soundtracks/album/tekken-5', platform: 'PlayStation', year: 2004 },
  { title: 'Bomberman Hero', sourceUrl: 'https://downloads.khinsider.com/game-soundtracks/album/bomberman-hero', platform: 'Nintendo 64', year: 1998 },
  { title: 'Metal Gear Solid 2', sourceUrl: 'https://downloads.khinsider.com/game-soundtracks/album/mgs2', platform: 'PlayStation', year: 2001 },
];

const mockConsoles = [
  { id: 'nintendo-nes', name: 'NES', url: 'https://downloads.khinsider.com/game-soundtracks/nintendo-nes', albumCount: 120 },
  { id: 'sony-playstation', name: 'PlayStation', url: 'https://downloads.khinsider.com/game-soundtracks/sony-playstation', albumCount: 850 },
];

// Register broad route first; Playwright matches last-registered first
test.beforeEach(async ({ page }) => {
  // Catch-all for catalog search queries
  await page.route('**/catalog?**', route => {
    const url = new URL(route.request().url());
    const q = url.searchParams.get('q') ?? '';
    const filtered = sampleEntries.filter(e => e.title.toLowerCase().includes(q.toLowerCase()));
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(mockCatalogPage(filtered)) });
  });
  // More specific routes registered after override the catch-all
  await page.route('**/catalog/sync', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ running: false, entries: 0, consoles: 0 }) })
  );
  await page.route('**/catalog/consoles', route =>
    route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(mockConsoles) })
  );
});

test('browse page shows catalog entries', async ({ page }) => {
  await page.goto('/browse');
  await expect(page.getByText('Tekken 5 Original Soundtrack')).toBeVisible();
  await expect(page.getByText('Bomberman Hero')).toBeVisible();
});

test('browse search filters entries', async ({ page }) => {
  await page.goto('/browse');
  await page.getByPlaceholder('Search albums…').fill('Tekken');
  await page.waitForTimeout(400); // debounce
  await expect(page.getByText('Tekken 5 Original Soundtrack')).toBeVisible();
  await expect(page.getByText('Bomberman Hero')).not.toBeVisible();
});

test('browse shows console chips', async ({ page }) => {
  await page.goto('/browse');
  await expect(page.locator('.chip', { hasText: 'NES' })).toBeVisible({ timeout: 5000 });
  await expect(page.locator('.chip', { hasText: 'PlayStation' })).toBeVisible();
});

test('browse has letter strip from A to Z', async ({ page }) => {
  await page.goto('/browse');
  await expect(page.locator('.letter', { hasText: /^A$/ })).toBeVisible();
  await expect(page.locator('.letter', { hasText: /^Z$/ })).toBeVisible();
});

test('browse has sync button', async ({ page }) => {
  await page.goto('/browse');
  await expect(page.getByRole('button', { name: /sync catalog/i })).toBeVisible();
});

test('clicking + button on entry triggers import', async ({ page }) => {
  await page.route('**/albums', route => {
    route.request().method() === 'POST'
      ? route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ jobId: 'j1', albumId: '', status: 'done' }) })
      : route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
  });

  await page.goto('/browse');
  const tekken = page.getByText('Tekken 5 Original Soundtrack');
  await tekken.hover();
  await page.locator('.import-btn').first().click();
  await expect(page.locator('.check').first()).toBeVisible({ timeout: 3000 });
});
