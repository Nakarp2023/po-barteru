import { chromium } from 'playwright';

const baseURL = process.env.BASE_URL || 'https://po-barteru-no-gestures-staging.onrender.com/';
const failures = [];
const browser = await chromium.launch({ headless: true });

async function checkViewport(name, viewport, isMobile = false) {
  const context = await browser.newContext({
    viewport,
    isMobile,
    deviceScaleFactor: isMobile ? 3 : 1,
    hasTouch: isMobile,
    reducedMotion: 'reduce'
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
