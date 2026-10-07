// End-to-end smoke of the Sendoff web app against the mock store, in headless Chromium.
//   npm run e2e            builds, serves dist/ on 4173, runs every check, exits non-zero on failure
//   E2E_BASE=http://... node e2e/smoke.mjs    against an already running server
// Screenshots land in e2e/shots/ (gitignored).
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, 'shots');
mkdirSync(out, { recursive: true });

let server;
let base = process.env.E2E_BASE;
if (!base) {
  base = 'http://localhost:4173';
  server = spawn('npx', ['vite', 'preview', '--port', '4173', '--strictPort'], { cwd: join(here, '..'), stdio: 'ignore' });
  for (let i = 0; i < 50; i++) {
    try { await fetch(base); break; } catch { await new Promise((r) => setTimeout(r, 200)); }
  }
}

const launchOpts = process.env.PLAYWRIGHT_CHROMIUM_PATH ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH } : {};
const browser = await chromium.launch(launchOpts);
let failures = 0;
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });

const step = async (name, fn) => { try { await fn(); console.log('ok  ', name); } catch (e) { failures++; console.log('FAIL', name, '\n    ', e.message.split('\n')[0]); } };
const shot = (n) => page.screenshot({ path: `${out}/${n}.png` });
const text = async (sel) => (await page.locator(sel).first().textContent())?.trim();

// 1. Reveal: Maria, opens now
await step('reveal: sealed stage renders', async () => {
  await page.goto(`${base}/s/maria-r/open?k=demo`);
  await page.waitForSelector('#sealed.active .envelope');
  if ((await text('#sealed .hint, #sealed p.ui')) !== 'Tap the seal') throw new Error('hint: ' + await text('#sealed p.ui'));
  if (await page.getAttribute('html', 'data-theme') !== 'midnight_toast') throw new Error('theme not applied');
  await shot('01-sealed');
});
await step('reveal: tap seal opens cover', async () => {
  await page.click('#sealed .envelope');
  await page.waitForSelector('#cover.active', { timeout: 5000 });
  if (!(await text('#cover h1'))?.includes('Maria Reyes')) throw new Error('no name');
  if (!(await text('#cover .ribbon span'))?.includes('6 people')) throw new Error('count: ' + await text('#cover .ribbon span'));
  await shot('02-cover');
});
await step('reveal: entries advance and retreat', async () => {
  await page.click('#cover');
  await page.waitForSelector('#entries.active .entry-page');
  if (await text('#entries .caption.center') !== '1 of 6') throw new Error(await text('#entries .caption.center'));
  if (!(await text('#entries .signature'))?.includes('Dan Okafor')) throw new Error('pinned entry not first');
  await shot('03-entry-1');
  await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowRight');
  await page.waitForSelector('#entries .voice');
  await shot('04-entry-voice');
  await page.click('#entries .voice .play');
  await page.waitForTimeout(600);
  const on = await page.locator('#entries .wave b.on').count();
  if (on === 0) throw new Error('waveform did not animate');
  await page.keyboard.press('ArrowRight');
  await page.waitForSelector('#entries .photos img');
  if (await page.locator('#entries .photos img').count() !== 3) throw new Error('photos');
  await shot('05-entry-photos');
  const topBefore = await page.evaluate(() => [...document.querySelectorAll('#entries .photos img')].findIndex((i) => i.style.zIndex === '3'));
  await page.locator('#entries .photos img').nth(topBefore).click();
  await page.waitForTimeout(100);
  const topAfter = await page.evaluate(() => [...document.querySelectorAll('#entries .photos img')].findIndex((i) => i.style.zIndex === '3'));
  if (topBefore === topAfter) throw new Error('photo shuffle did not change the top photo');
  await page.keyboard.press('ArrowRight');
  await page.waitForSelector('#entries .video');
  await shot('06-entry-video');
  await page.keyboard.press('ArrowLeft');
  await page.waitForSelector('#entries .photos');
  for (let i = 0; i < 3; i++) await page.keyboard.press('ArrowRight');
  await page.waitForSelector('#kept.active');
  if (await text('#kept h1') !== 'Kept for you.') throw new Error('kept');
  await shot('07-kept');
});
await step('reveal: read it again returns to cover', async () => {
  await page.click('#kept .btn:not(.quiet)');
  await page.waitForSelector('#cover.active');
});
await step('reveal: swipe advances', async () => {
  await page.touchscreen.tap(195, 400);
  await page.waitForSelector('#entries.active');
  const before = await text('#entries .caption.center');
  await page.evaluate(() => {
    const t = (type, x) => document.dispatchEvent(new TouchEvent(type, { touches: type === 'touchstart' ? [new Touch({ identifier: 1, target: document.body, clientX: x, clientY: 400 })] : [], changedTouches: [new Touch({ identifier: 1, target: document.body, clientX: x, clientY: 400 })], bubbles: true }));
    t('touchstart', 300); t('touchend', 100);
  });
  await page.waitForTimeout(500);
  const after = await text('#entries .caption.center');
  if (before === after) throw new Error(`swipe: ${before} -> ${after}`);
});

// 2. Reveal: Mr. Patel, sealed with countdown
await step('reveal: sealed countdown refuses to open', async () => {
  await page.goto(`${base}/s/mr-patel/open?k=demo`);
  await page.waitForSelector('#sealed.active .envelope.locked');
  if (await page.locator('.countdown div').count() < 3) throw new Error('no countdown');
  if (!(await text('#sealed p.ui'))?.startsWith('Sealed until')) throw new Error(await text('#sealed p.ui'));
  await page.click('#sealed .envelope');
  await page.waitForTimeout(800);
  if (await page.locator('#cover.active').count()) throw new Error('opened early');
  if (await page.getAttribute('html', 'data-theme') !== 'chalk') throw new Error('theme');
  await shot('08-sealed-countdown');
});

// 3. Contribute: Jo
await step('contribute: form renders with prompts', async () => {
  await page.goto(`${base}/s/jo-moves?t=demo`);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForSelector('#body');
  if ((await page.locator('.chip').count()) !== 4) throw new Error('prompts');
  if (!(await page.locator('.sticky .btn').isDisabled())) throw new Error('button should be disabled');
  await shot('09-contribute-empty');
});
await step('contribute: prompt fills textarea, submit enables, thanks page', async () => {
  await page.click('.chip >> nth=1');
  const v = await page.inputValue('#body');
  if (!v.startsWith("The thing you'll miss most")) throw new Error(v);
  await page.fill('#body', "You said the deadline is real, the panic is optional. Still on my monitor.");
  await page.fill('#name', 'Priya N.');
  await page.fill('#rel', 'Your 2019 intern');
  if (await page.locator('.sticky .btn').isDisabled()) throw new Error('button still disabled');
  await shot('10-contribute-filled');
  await page.click('.sticky .btn');
  await page.waitForSelector('text=It\'s in the envelope.', { timeout: 5000 });
  await shot('11-contribute-thanks');
});
await step('contribute: reload shows thanks (remembered), change mine prefills', async () => {
  await page.reload();
  await page.waitForSelector('text=It\'s in the envelope.');
  await page.click('text=Change mine');
  await page.waitForSelector('#body');
  if (await page.inputValue('#name') !== 'Priya N.') throw new Error('not prefilled');
  if (await text('.sticky .btn') !== 'Save changes') throw new Error(await text('.sticky .btn'));
});
await step('contribute: photo attach via file chooser', async () => {
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), page.click('.attach button >> nth=0')]);
  await chooser.setFiles({ name: 'a.png', mimeType: 'image/png', buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64') });
  await page.waitForSelector('.thumb img');
  await shot('12-contribute-photo');
  await page.click('.sticky .btn');
  await page.waitForSelector('text=It\'s in the envelope.');
});
await step('contribute: sealed sendoff shows sealed page', async () => {
  await page.goto(`${base}/s/mr-patel?t=demo`);
  await page.waitForSelector('text=It\'s sealed.');
});
await step('contribute: unknown slug shows not found', async () => {
  await page.goto(`${base}/s/nope?t=demo`);
  await page.waitForSelector("text=We couldn't find that Sendoff.");
});

// 4. QR
await step('qr: card renders a code', async () => {
  await page.goto(`${base}/s/jo-moves/qr?t=demo`);
  await page.waitForSelector('.qr-card img');
  const src = await page.getAttribute('.qr-card img', 'src');
  if (!src?.startsWith('data:image/png')) throw new Error('no png');
  if (!(await text('.qr-card .url'))?.includes('/s/jo-moves?t=demo')) throw new Error(await text('.qr-card .url'));
  await shot('13-qr');
});

// 5. Landing, themes
await step('landing renders demo links in mock', async () => {
  await page.goto(`${base}/`);
  await page.waitForSelector('.demo-links a');
  await shot('14-landing');
});
await step('desktop reveal (letterpress via jo)', async () => {
  const d = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await d.goto(`${base}/s/maria-r/open?k=demo`);
  await d.waitForSelector('#sealed.active .envelope');
  await d.screenshot({ path: `${out}/15-desktop-sealed.png` });
  await d.close();
});

console.log(errors.length ? `\nPAGE ERRORS:\n${errors.join('\n')}` : '\nno page errors');
await browser.close();
server?.kill();
process.exit(failures || errors.length ? 1 : 0);
