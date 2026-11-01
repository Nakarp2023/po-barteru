import { chromium } from 'playwright';

const baseURL = process.env.BASE_URL || 'local';
const failures = [];
const browser = await chromium.launch({ headless: true });

async function checkViewport(name, viewport, isMobile = false) {
  const context = await browser.newContext({
    viewport,
    isMobile,
    deviceScaleFactor: isMobile ? 3 : 1,
    hasTouch: isMobile,
    reducedMotion: 'no-preference'
  });
  const page = await context.newPage();
  const pageErrors = [];
  page.on('pageerror', error => pageErrors.push(error.message));

  const response = await page.goto(baseURL, { waitUntil: 'domcontentloaded', timeout: 60000 });
  if (!response || !response.ok()) {
    failures.push(`${name}: HTTP response ${response?.status() ?? 'missing'}`);
  }

  await page.waitForLoadState('load', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(1200);

  const title = await page.title();
  if (!title.includes('ПО БАРТЕРУ')) failures.push(`${name}: unexpected title "${title}"`);

  const metrics = await page.evaluate(() => ({
    width: document.documentElement.clientWidth,
    documentWidth: document.documentElement.scrollWidth,
    bodyWidth: document.body?.scrollWidth ?? 0,
    lang: document.documentElement.lang,
    viewport: document.querySelector('meta[name="viewport"]')?.content ?? ''
  }));

  if (metrics.lang !== 'ru') failures.push(`${name}: document language is not ru`);
  if (!metrics.viewport) failures.push(`${name}: viewport meta tag is missing`);
  if (metrics.documentWidth > metrics.width + 2 || metrics.bodyWidth > metrics.width + 2) {
    failures.push(`${name}: horizontal overflow (viewport ${metrics.width}px, document ${metrics.documentWidth}px, body ${metrics.bodyWidth}px)`);
  }
  for (const error of pageErrors) failures.push(`${name}: uncaught browser error: ${error}`);

  // Check the authentication controls without sending emails or changing account state.
  const authChecks = [
    '#authEmail',
    '#authPassword',
    '#authPasswordLogin',
    '#authPasswordSignup',
    '#authPasswordReset',
    '#authSend'
  ];
  for (const selector of authChecks) {
    if (!(await page.locator(selector).count())) failures.push(`${name}: authentication control is missing ${selector}`);
  }
  if (await page.locator('#authEmail').getAttribute('type') !== 'email') {
    failures.push(`${name}: email field is not typed as email`);
  }
  if (await page.locator('#authPassword').getAttribute('type') !== 'password') {
    failures.push(`${name}: password field is not masked`);
  }

  // Navigation regression: main sections are tap-only, with no horizontal page motion.
  const tabs = page.locator('.bottom .nav[data-page]');
  const tabCount = await tabs.count();
  if (tabCount < 4) failures.push(`${name}: expected primary navigation tabs were not found`);
  else {
    for (const target of ['profile', 'chats', 'my-listings', 'favorites', 'home']) {
      const tab = page.locator(`.bottom .nav[data-page="${target}"]`);
      if (!(await tab.count())) {
        failures.push(`${name}: missing navigation tab ${target}`);
        continue;
      }
      await tab.click();
      await page.waitForTimeout(80);
      if (!(await tab.evaluate(el => el.classList.contains('active')))) {
        failures.push(`${name}: tap did not activate ${target} tab`);
      }
      const motion = await page.locator('main.app:not([inert])').evaluate(el => {
        const transform = getComputedStyle(el).transform;
        const values = transform.startsWith('matrix(')
          ? transform.slice(7, -1).split(',').map(Number)
          : [];
        const nav = document.querySelector('.bottom');
        const pageAnimation = el.getAnimations().some(animation => {
          const duration = animation.effect?.getTiming()?.duration;
          return typeof duration === 'number' && duration >= 250 && duration <= 320 && animation.playState === 'running';
        });
        return {
          transform,
          translateX: values.length === 6 ? values[4] : 0,
          pageAnimation,
          navPosition: getComputedStyle(nav).position,
          indicatorTransitionDuration: getComputedStyle(nav, '::before').transitionDuration
        };
      });
      if (!motion.pageAnimation || Math.abs(motion.translateX) < 1) {
        failures.push(`${name}: tap did not start the expected smooth page transition after ${target} tab tap`);
      }
      if (motion.navPosition !== 'fixed') {
        failures.push(`${name}: bottom navigation is not fixed during the page transition`);
      }
      if (motion.indicatorTransitionDuration.split(',').every(value => parseFloat(value) <= 0)) {
        failures.push(`${name}: Liquid Glass active-tab indicator has no transition`);
      }
      await page.waitForFunction(() => {
        const el = document.querySelector('main.app:not([inert])');
        return !el || !el.getAnimations().some(animation => {
          const duration = animation.effect?.getTiming()?.duration;
          return typeof duration === 'number' && duration >= 250 && duration <= 320 && animation.playState === 'running';
        });
      }, null, { timeout: 2500 }).catch(() => {});
      const settledTransform = await page.locator('main.app:not([inert])').evaluate(el => getComputedStyle(el).transform);
      if (settledTransform !== 'none' && settledTransform !== 'matrix(1, 0, 0, 1, 0, 0)') {
        failures.push(`${name}: app shell did not return to its neutral transform after ${target} tab transition`);
      }
    }

    // Notifications are intentionally opened from the top-bar bell, not a bottom tab.
  const notificationEntry = page.locator('#notificationTop');
  if (!(await notificationEntry.count())) failures.push(`${name}: top-bar notifications entry is missing`);
  else if ((await notificationEntry.getAttribute('aria-label')) !== 'Уведомления') {
    failures.push(`${name}: top-bar notifications entry has an unexpected accessible label`);
  }

  // Synthetic horizontal touch movement on the app shell must not change the active tab.
    const beforeSwipe = await page.locator('.bottom .nav.active').getAttribute('data-page');
    await page.locator('main.app:not([inert])').evaluate(el => {
      const makePointerEvent = (type, x) => new PointerEvent(type, {
        bubbles: true, cancelable: true, pointerId: 77, pointerType: 'touch',
        isPrimary: true, clientX: x, clientY: 420, button: 0
      });
      el.dispatchEvent(makePointerEvent('pointerdown', 330));
      document.dispatchEvent(makePointerEvent('pointermove', 45));
      document.dispatchEvent(makePointerEvent('pointerup', 45));
      const makeTouchEvent = (type, x) => {
        const event = new Event(type, { bubbles: true, cancelable: true });
        Object.defineProperty(event, 'touches', { value: type === 'touchend' ? [] : [{ clientX: x, clientY: 420 }] });
        Object.defineProperty(event, 'changedTouches', { value: [{ clientX: x, clientY: 420 }] });
        return event;
      };
      el.dispatchEvent(makeTouchEvent('touchstart', 330));
      document.dispatchEvent(makeTouchEvent('touchmove', 45));
      document.dispatchEvent(makeTouchEvent('touchend', 45));
    });
    await page.waitForTimeout(100);
    const afterSwipe = await page.locator('.bottom .nav.active').getAttribute('data-page');
    if (afterSwipe !== beforeSwipe) failures.push(`${name}: horizontal touch movement changed the primary section from ${beforeSwipe} to ${afterSwipe}`);
  }

  // Catalog controls: read-only search/filter/sort requests only; never submit or mutate records.
  const filterToggle = page.locator('#advancedSearchToggle');
  if (await filterToggle.count()) {
    await filterToggle.click();
    const panel = page.locator('#advancedSearchPanel');
    try {
      await panel.waitFor({ state: 'visible', timeout: 4000 });
      for (const selector of ['#advancedCity', '#filterCityOnly', '#filterSort', '#advancedMinPrice', '#advancedMaxPrice', '#resetAdvancedSearch', '#applyFilters']) {
        if (!(await panel.locator(selector).count())) failures.push(`${name}: catalog filter control is missing ${selector}`);
      }
      const sort = panel.locator('#filterSort');
      await sort.selectOption('newest');
      await panel.locator('#applyFilters').click();
      await page.waitForTimeout(900);
      if (await page.locator('#catalogStatus.is-error').count()) failures.push(`${name}: catalog returned an error after applying newest sort`);
      await filterToggle.click();
      await panel.waitFor({ state: 'visible', timeout: 3000 });
      await panel.locator('#resetAdvancedSearch').click();
      await page.waitForTimeout(900);
      if (await page.locator('#catalogStatus.is-error').count()) failures.push(`${name}: catalog returned an error after resetting filters`);
      await filterToggle.click();
      await panel.waitFor({ state: 'hidden', timeout: 3000 });
    } catch (error) {
      failures.push(`${name}: catalog filters did not operate correctly: ${error.message}`);
    }
  } else failures.push(`${name}: catalog filter toggle was not found`);

  const searchInput = page.locator('#q');
  if (await searchInput.count()) {
    await searchInput.click(); // The field is readonly until a real focus, to suppress browser autofill.
    await searchInput.fill('qa-no-match-2026-smoke');
    await page.locator('#searchBtn').click();
    await page.waitForTimeout(900);
    if (await page.locator('#catalogStatus.is-error').count()) failures.push(`${name}: catalog search returned a server error`);
    await searchInput.fill('');
    await page.locator('#searchBtn').click();
    await page.waitForTimeout(900);
    if (await page.locator('#catalogStatus.is-error').count()) failures.push(`${name}: catalog failed to reload after clearing search`);
  } else failures.push(`${name}: catalog search field was not found`);

  // Exercise the listing form without authentication or database writes.
  const addButton = page.locator('#addTop');
  if (await addButton.count()) {
    await addButton.click({ timeout: 10000 }).catch(() => {});
    const form = page.locator('#modal.open #form');
    try {
      await form.waitFor({ state: 'visible', timeout: 5000 });
      for (const selector of ['[name="title"]', '[name="category"]', '[name="want"]', '[name="city"]', '#listingImages', '#listingSubmit']) {
        if (!(await form.locator(selector).count())) failures.push(`${name}: listing form is missing ${selector}`);
      }
      const imageInput = form.locator('#listingImages');
      if ((await imageInput.getAttribute('accept')) !== 'image/*') failures.push(`${name}: listing photo input does not restrict selection to images`);
      const imageHint = await imageInput.locator('xpath=following-sibling::small').textContent().catch(() => '');
      if (!imageHint?.includes('5 МБ')) failures.push(`${name}: listing photo size guidance is missing`);
      for (const selector of ['[name="title"]', '[name="want"]', '[name="city"]']) {
        if ((await form.locator(selector).getAttribute('required')) === null) failures.push(`${name}: required validation is missing for ${selector}`);
      }
      const limits = {
        '[name="title"]': '80',
        '[name="want"]': '120',
        '[name="description"]': '500'
      };
      for (const [selector, expected] of Object.entries(limits)) {
        if ((await form.locator(selector).getAttribute('maxlength')) !== expected) {
          failures.push(`${name}: unexpected maxlength for ${selector}`);
        }
      }
      if ((await form.locator('[name="price"]').getAttribute('min')) !== '0') {
        failures.push(`${name}: price field does not prevent negative values`);
      }
      const invalidEmptyForm = await form.evaluate(element => !element.checkValidity());
      if (!invalidEmptyForm) failures.push(`${name}: empty listing form unexpectedly passes browser validation`);
      await page.locator('#cancel').click({ timeout: 5000 });
      if (await page.locator('#modal.open').count()) failures.push(`${name}: listing form did not close after Cancel`);
    } catch (error) {
      failures.push(`${name}: listing form did not open correctly: ${error.message}`);
    }
  } else {
    failures.push(`${name}: top-level add-listing button was not found`);
  }

  await page.screenshot({ path: `artifacts/${name}.png`, fullPage: true }).catch(() => {});
  console.log(JSON.stringify({ test: name, status: failures.some(x => x.startsWith(name + ':')) ? 'FAIL' : 'PASS', http: response?.status(), title, ...metrics, pageErrors }, null, 2));
  await context.close();
}

try {
  await checkViewport('desktop', { width: 1440, height: 900 });
  await checkViewport('iphone-14-pro', { width: 393, height: 852 }, true);
} finally {
  await browser.close();
}

if (failures.length) {
  console.error('\nSMOKE TEST FAILURES:\n' + failures.map(x => '- ' + x).join('\n'));
  process.exit(1);
}
console.log('\nAll staging smoke checks passed.');
