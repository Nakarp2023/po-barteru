import { test, expect } from '@playwright/test';

test('screen stage is isolated from the app shell and fixed navigation', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
  expect(response).not.toBeNull();
  expect(response.status()).toBeLessThan(400);
  await expect(page.locator('main.app > header.top')).toBeVisible();
  await expect(page.locator('main.app > #poScreenStage')).toBeVisible();
  await expect(page.locator('main.app > #poScreenStage')).toHaveCount(1);
  await expect(page.locator('#poScreenStage')).toHaveAttribute('data-navigation-build', 'nav-stage-v1-20261031-01');
  await expect(page.locator('body > nav.bottom')).toBeVisible();

  const structure = await page.evaluate(() => ({
    headerInsideStage: !!document.querySelector('#poScreenStage header.top'),
    navInsideStage: !!document.querySelector('#poScreenStage + nav.bottom'),
    stageParent: document.querySelector('#poScreenStage')?.parentElement?.tagName,
    diagnostics: window.poNavigationDiagnostics?.(),
  }));
  expect(structure.headerInsideStage).toBe(false);
  expect(structure.navInsideStage).toBe(false);
  expect(structure.stageParent).toBe('MAIN');
  expect(structure.diagnostics?.installed).toBe(true);
  expect(structure.diagnostics?.stage).toBe('poScreenStage');
  expect(errors).toEqual([]);
});

test('tab navigation and browser Back restore the previous screen', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="favorites"]').click();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  await page.goBack();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('home');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
});

test('reduced-motion navigation remains functional without a transition lock', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="my-listings"]').click();
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.currentPage).toBe('my-listings');
  expect(diagnostics?.transitioning).toBe(false);
  expect(diagnostics?.gestureActive).toBe(false);
});

test('navigation never creates cloned screen snapshots', async ({ page }) => {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="profile"]').click();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  expect(await page.locator('.po-nav-snapshot-viewport').count()).toBe(0);
  expect(await page.locator('#poScreenStage').count()).toBe(1);
});

test('horizontal pointer swipe changes one adjacent tab and releases the transition lock', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const heading = await page.locator('#homeHero h1').boundingBox();
  expect(heading).not.toBeNull();
  const x = heading.x + heading.width * 0.82;
  const y = heading.y + heading.height * 0.5;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x - 125, y, { steps: 8 });
  await page.mouse.up();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.gestureActive).toBe(false);
  expect(diagnostics?.pointerId).toBeNull();
});

test('vertical pointer movement does not trigger horizontal page navigation', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const heading = await page.locator('#homeHero h1').boundingBox();
  expect(heading).not.toBeNull();
  const x = heading.x + heading.width * 0.82;
  const y = heading.y + heading.height * 0.5;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x, y + 110, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(300);
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.currentPage).toBe('home');
  expect(diagnostics?.transitioning).toBe(false);
  expect(diagnostics?.gestureActive).toBe(false);
});
