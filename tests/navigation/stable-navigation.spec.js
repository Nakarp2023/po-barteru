import { test, expect } from '@playwright/test';

test('primary navigation uses simple taps and keeps the app shell fixed', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.setViewportSize({ width: 390, height: 844 });
  const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
  expect(response).not.toBeNull();
  expect(response.status()).toBeLessThan(400);
  await expect(page.locator('main.app > header.top')).toBeVisible();
  await expect(page.locator('main.app > #poScreenStage')).toBeVisible();
  await expect(page.locator('body > nav.bottom')).toBeVisible();
  await expect(page.locator('#poScreenStage')).toHaveAttribute('data-navigation-build', 'simple-nav-v1-20261031-01');
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.mode).toBe('tap-only');
  expect(diagnostics?.gestureActive).toBe(false);
  expect(errors).toEqual([]);
});

test('all five main sections can be opened by tapping their tab', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  for (const target of ['favorites', 'my-listings', 'chats', 'profile', 'home']) {
    await page.locator(`.bottom .nav[data-page="${target}"]`).click();
    await expect(page.locator(`.bottom .nav[data-page="${target}"]`)).toHaveClass(/active/);
    await expect.poll(() => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe(target);
    const geometry = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      width: document.documentElement.scrollWidth,
      header: document.querySelector('header.top')?.getBoundingClientRect().left,
      nav: document.querySelector('.bottom')?.getBoundingClientRect().left,
    }));
    expect(geometry.width).toBeLessThanOrEqual(geometry.viewport + 1);
    expect(geometry.header).toBeGreaterThanOrEqual(-1);
    expect(geometry.nav).toBeGreaterThanOrEqual(-1);
  }
});

test('horizontal swipes no longer change primary tabs', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const box = await page.locator('#poScreenStage').boundingBox();
  expect(box).not.toBeNull();
  const x = box.x + box.width * 0.75;
  const y = Math.max(box.y + 80, Math.min(box.y + 180, box.y + box.height - 20));
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x - 140, y, { steps: 8 });
  await page.mouse.up();
  await expect.poll(() => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('home');
  expect(await page.locator('#poScreenStage').count()).toBe(1);
  expect(await page.locator('.po-nav-snapshot-viewport').count()).toBe(0);
});

test('browser Back restores the previous tab after a normal tab tap', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="favorites"]').click();
  await expect.poll(() => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
  await page.goBack();
  await expect.poll(() => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('home');
  await expect(page.locator('.bottom .nav[data-page="home"]')).toHaveClass(/active/);
});

test('navigation remains functional with reduced motion enabled', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="profile"]').click();
  await expect.poll(() => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('profile');
  expect(await page.evaluate(() => window.poNavigationDiagnostics?.().gestureActive)).toBe(false);
});
