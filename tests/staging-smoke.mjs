import { chromium, devices } from 'playwright';

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
