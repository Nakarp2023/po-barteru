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
  await expect(page.locator('#poScreenStage')).toHaveAttribute('data-navigation-build', 'nav-stage-v1-20261031-06');
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

test('tab changes use captured old and new screen surfaces when supported', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const support = await page.evaluate(() => ({
    api: typeof document.startViewTransition === 'function',
    name: getComputedStyle(document.querySelector('#poScreenStage')).viewTransitionName,
  }));
  expect(support.name).toBe('po-screen');
  if (!support.api) test.skip();
  await page.evaluate(() => {
    const native = document.startViewTransition.bind(document);
    window.__poViewTransitionCalls = 0;
    document.startViewTransition = callback => {
      window.__poViewTransitionCalls += 1;
      return native(callback);
    };
  });
  await page.locator('.bottom .nav[data-page="favorites"]').click();
  await expect.poll(async () => page.evaluate(() => window.__poViewTransitionCalls)).toBe(1);
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  const clean = await page.evaluate(() => ({
    transform: document.querySelector('#poScreenStage').style.transform,
    directionClasses: document.documentElement.classList.contains('po-nav-next') || document.documentElement.classList.contains('po-nav-prev'),
  }));
  expect(clean.transform).toBe('');
  expect(clean.directionClasses).toBe(false);
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

test('lost focus cancels an active drag without leaving the screen displaced', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const heading = await page.locator('#homeHero h1').boundingBox();
  expect(heading).not.toBeNull();
  const x = heading.x + heading.width * 0.82;
  const y = heading.y + heading.height * 0.5;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x - 70, y, { steps: 6 });
  const active = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(active?.gestureActive).toBe(true);
  await page.evaluate(() => window.dispatchEvent(new Event('blur')));
  const recovered = await page.evaluate(() => ({
    diagnostics: window.poNavigationDiagnostics?.(),
    inlineTransform: document.querySelector('#poScreenStage')?.style.transform || '',
  }));
  expect(recovered.diagnostics?.currentPage).toBe('home');
  expect(recovered.diagnostics?.gestureActive).toBe(false);
  expect(recovered.diagnostics?.transitioning).toBe(false);
  expect(recovered.inlineTransform).toBe('');
  await page.mouse.up();
});

test('nested profile back swipe works when it starts over scrollable help content', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="profile"]').click();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('profile');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  await page.evaluate(() => {
    const dashboard = document.querySelector('#profileDashboard');
    const help = document.querySelector('#profileInfoHelpPanel');
    if (dashboard) {
      dashboard.hidden = false;
      dashboard.classList.add('profile-show-settings');
    }
    if (help) help.hidden = false;
  });
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().nested)).toBe(true);
  const details = page.locator('#profileInfoHelpPanel details').first();
  await expect(details).toBeVisible();
  await details.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
  const box = await details.boundingBox();
  expect(box).not.toBeNull();
  const x = Math.max(24, Math.min(72, box.x + 16));
  const y = box.y + box.height * 0.5;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + 125, y, { steps: 8 });
  await page.mouse.up();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().nested)).toBe(false);
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.currentPage).toBe('profile');
  expect(diagnostics?.gestureActive).toBe(false);
});

test('reverse horizontal swipe returns from favorites to home without a tab tap', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('.bottom .nav[data-page="favorites"]').click();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  const heading = await page.locator('#poScreenStage').boundingBox();
  expect(heading).not.toBeNull();
  const x = Math.max(100, Math.min(heading.x + heading.width * 0.75, 330));
  const y = Math.max(150, Math.min(heading.y + 90, 700));
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + 130, y, { steps: 8 });
  await page.mouse.up();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('home');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.gestureActive).toBe(false);
});

test('first swipe after a fresh load is handled before any tab interaction', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const initial = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(initial?.installed).toBe(true);
  expect(initial?.currentPage).toBe('home');
  const heading = await page.locator('#homeHero h1').boundingBox();
  expect(heading).not.toBeNull();
  const x = heading.x + heading.width * 0.82;
  const y = heading.y + heading.height * 0.5;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x - 130, y, { steps: 8 });
  await page.mouse.up();
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
});

test('swipe navigation is bidirectional across consecutive gestures', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  const drag = async (selector, deltaX) => {
    const box = await page.locator(selector).boundingBox();
    expect(box).not.toBeNull();
    const x = Math.max(100, Math.min(box.x + box.width * 0.78, 330));
    const y = Math.max(160, Math.min(box.y + box.height * 0.5, 720));
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + deltaX, y, { steps: 8 });
    await page.mouse.up();
  };
  await drag('#homeHero h1', -130);
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('favorites');
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().transitioning)).toBe(false);
  await drag('#poScreenStage', 130);
  await expect.poll(async () => page.evaluate(() => window.poNavigationDiagnostics?.().currentPage)).toBe('home');
  const diagnostics = await page.evaluate(() => window.poNavigationDiagnostics?.());
  expect(diagnostics?.transitioning).toBe(false);
  expect(diagnostics?.gestureActive).toBe(false);
});
