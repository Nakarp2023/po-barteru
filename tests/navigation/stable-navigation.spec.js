import { test, expect } from '@playwright/test';

const tab = pageName => `.bottom .nav[data-page="${pageName}"]`;

async function openApp(page) {
  await page.setViewportSize({ width: 390, height: 844 });
  const response = await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() =>
    typeof window.poCanNavigateBack === 'function' &&
    typeof window.setPage === 'function' &&
    !!document.querySelector('#poScreenStage')
  );
  return response;
}

test('navigation shell is stable and the bottom bar is the only primary tab control', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const response = await openApp(page);
  expect(response).not.toBeNull();
  expect(response.status()).toBeLessThan(400);
  await page.waitForFunction(() => typeof window.poCanNavigateBack === 'function');
  await expect(page.locator('main.app > header.top')).toBeVisible();
  await expect(page.locator('main.app > #poScreenStage')).toBeVisible();
  await expect(page.locator('body > nav.bottom')).toBeVisible();
  await expect(page.locator('#poScreenStage')).toHaveAttribute('data-navigation-build', 'nav-stage-v2-tabs-only-20261101');
  expect(await page.locator('.bottom .nav').count()).toBeGreaterThanOrEqual(5);
  expect(errors).toEqual([]);
});

test('primary tabs switch only by tapping and never slide the screen', async ({ page }) => {
  await openApp(page);
  const targets = ['favorites', 'my-listings', 'chats', 'profile', 'home'];
  for (const target of targets) {
    await page.locator(tab(target)).click();
    await expect(page.locator(tab(target))).toHaveClass(/active/);
    await expect(page.locator('#poScreenStage')).toBeVisible();
    const state = await page.evaluate(() => {
      const stage = document.querySelector('#poScreenStage');
      const active = document.querySelector('.bottom .nav.active');
      return {
        active: active?.dataset.page || null,
        transform: stage ? getComputedStyle(stage).transform : null,
        width: stage?.getBoundingClientRect().width || 0,
        height: stage?.getBoundingClientRect().height || 0,
        hasVisibleContent: !!stage && [...stage.children].some(node => !node.hidden && getComputedStyle(node).display !== 'none'),
      };
    });
    expect(state.active).toBe(target);
    expect(state.transform).toBe('none');
    expect(state.width).toBeGreaterThan(0);
    expect(state.height).toBeGreaterThan(0);
    expect(state.hasVisibleContent).toBe(true);
  }
});

test('browser Back restores the previous primary tab after a tab tap', async ({ page }) => {
  await openApp(page);
  await expect(page.locator(tab('home'))).toHaveClass(/active/);
  await page.locator(tab('favorites')).click();
  await expect(page.locator(tab('favorites'))).toHaveClass(/active/);
  await page.evaluate(() => window.history.back());
  await expect(page.locator(tab('home'))).toHaveClass(/active/);
  await expect(page.locator('#homeHero')).toBeVisible();
});

test('reduced-motion preference does not block tab switching', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await openApp(page);
  await page.locator(tab('my-listings')).click();
  await expect(page.locator(tab('my-listings'))).toHaveClass(/active/);
  await expect(page.locator('#poScreenStage')).toBeVisible();
});

test('repeated tab taps do not leave a blank or displaced screen', async ({ page }) => {
  await openApp(page);
  for (const target of ['favorites', 'home', 'profile', 'chats', 'my-listings', 'favorites', 'home']) {
    await page.locator(tab(target)).click();
    await expect(page.locator(tab(target))).toHaveClass(/active/);
    const visible = await page.locator('#poScreenStage').evaluate(stage => {
      const rect = stage.getBoundingClientRect();
      const content = [...stage.children].filter(node => !node.hidden && getComputedStyle(node).display !== 'none');
      return rect.width > 0 && rect.height > 0 && content.length > 0;
    });
    expect(visible).toBe(true);
  }
});

test('primary navigation contains no swipe-to-switch or drag controller', async ({ page }) => {
  await openApp(page);
  const sourceState = await page.evaluate(() => ({
    dragClass: document.querySelector('.bottom')?.classList.contains('nav-dragging') || false,
    transformName: getComputedStyle(document.querySelector('#poScreenStage')).viewTransitionName,
    snapshots: document.querySelectorAll('.po-nav-snapshot-viewport').length,
    primarySwipeController: !!window.poPrimaryTabSwipeNavigation,
  }));
  expect(sourceState.dragClass).toBe(false);
  expect(sourceState.transformName).toBe('none');
  expect(sourceState.snapshots).toBe(0);
  expect(sourceState.primarySwipeController).toBe(false);
});
