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
// Demo photos come from Unsplash; serve a local stand-in so the test never depends on the network.
// E2E_LIVE_IMAGES=1 lets the real photos through, for screenshots worth looking at.
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const routeImages = (c) => process.env.E2E_LIVE_IMAGES ? null : c.route('https://images.unsplash.com/**', (r) => r.fulfill({ contentType: 'image/png', body: png }));
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
await routeImages(ctx);
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });

const step = async (name, fn) => { try { await fn(); console.log('ok  ', name); } catch (e) { failures++; console.log('FAIL', name, '\n    ', e.message.split('\n')[0]); } };
// Let page turns and fades finish (endless ones, like the loading pulse, are skipped) and images land.
const settle = (p) => p.evaluate(() => Promise.race([
  Promise.all(document.getAnimations().filter((a) => a.effect?.getComputedTiming().endTime !== Infinity).map((a) => a.finished.catch(() => {}))),
  new Promise((r) => setTimeout(r, 1500)),
]));
const shot = async (n) => { await settle(page); await page.screenshot({ path: `${out}/${n}.png` }); };
const text = async (sel) => (await page.locator(sel).first().textContent())?.trim();
/** Press and hold the seal for `ms`, the way a recipient opens it. */
const hold = async (p, ms) => {
  const box = await p.locator('#sealed .seal').boundingBox();
  await p.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await p.mouse.down();
  await p.waitForTimeout(ms);
  await p.mouse.up();
};

// 1. Reveal: Maria, opens now
await step('reveal: sealed stage renders', async () => {
  await page.goto(`${base}/s/maria-r/open?k=demo`);
  await page.waitForSelector('#sealed.active .seal');
  if ((await text('#sealed .hint')) !== 'Press and hold the seal') throw new Error('hint: ' + await text('#sealed .hint'));
  if (!(await page.locator('#sealed').getAttribute('class')).includes('has-photo')) throw new Error('no photo behind the seal');
  if (await page.getAttribute('html', 'data-theme') !== 'midnight_toast') throw new Error('theme not applied');
  await shot('01-sealed');
});
await step('reveal: a short press does not open it, a hold does', async () => {
  await hold(page, 250);
  await page.waitForTimeout(400);
  if (await page.locator('#cover.active').count()) throw new Error('opened on a short press');
  if ((await text('#sealed .hint')) !== 'Press and hold the seal') throw new Error('hint did not reset: ' + await text('#sealed .hint'));
  await hold(page, 1200);
  await page.waitForSelector('#cover.active', { timeout: 5000 });
  if (!(await text('#cover h1'))?.includes('Maria Reyes')) throw new Error('no name');
  if (!(await text('#cover [data-count]'))?.includes('6 people')) throw new Error('count: ' + await text('#cover [data-count]'));
  await shot('02-cover');
});
await step('reveal: entries advance and retreat', async () => {
  await page.click('#cover .btn');
  await page.waitForSelector('#entries.active .entry-page');
  if (await text('.topbar .count') !== '1 of 6') throw new Error(await text('.topbar .count'));
  if (!(await text('#entries .sig'))?.includes('Dan Okafor')) throw new Error('pinned entry not first');
  if (await page.locator('.segments b.on').count() !== 1) throw new Error('progress segments');
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
  const shown = () => page.evaluate(() => [...document.querySelectorAll('#entries .photos img')].findIndex((i) => i.classList.contains('on')));
  const before = await shown();
  await page.click('#entries .photos');
  await page.waitForTimeout(100);
  if (before === await shown()) throw new Error('tapping the photo did not show the next one');
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
  await page.click('#kept .btn.primary');
  await page.waitForSelector('#cover.active');
});
await step('reveal: swipe advances', async () => {
  await page.touchscreen.tap(195, 400);
  await page.waitForSelector('#entries.active');
  const before = await text('.topbar .count');
  await page.evaluate(() => {
    const t = (type, x) => document.dispatchEvent(new TouchEvent(type, { touches: type === 'touchstart' ? [new Touch({ identifier: 1, target: document.body, clientX: x, clientY: 400 })] : [], changedTouches: [new Touch({ identifier: 1, target: document.body, clientX: x, clientY: 400 })], bubbles: true }));
    t('touchstart', 300); t('touchend', 100);
  });
  await page.waitForTimeout(500);
  const after = await text('.topbar .count');
  if (before === after) throw new Error(`swipe: ${before} -> ${after}`);
});

// 2. Reveal: Mr. Patel, sealed with countdown
await step('reveal: sealed countdown refuses to open', async () => {
  await page.goto(`${base}/s/mr-patel/open?k=demo`);
  await page.waitForSelector('#sealed.active .seal.locked');
  if (await page.locator('.countdown div').count() < 3) throw new Error('no countdown');
  if (!(await text('#sealed .hint'))?.startsWith('Sealed until')) throw new Error(await text('#sealed .hint'));
  if (await text('#sealed .seal') !== 'P') throw new Error('seal initial should skip the title: ' + await text('#sealed .seal'));
  await hold(page, 1200);
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
await step('desktop reveal opens from the keyboard', async () => {
  const dctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  await routeImages(dctx);
  const d = await dctx.newPage();
  await d.goto(`${base}/s/maria-r/open?k=demo`);
  await d.waitForSelector('#sealed.active .seal');
  await d.screenshot({ path: `${out}/15-desktop-sealed.png` });
  await d.focus('#sealed .seal');
  await d.keyboard.press('Enter');
  await d.waitForSelector('#cover.active', { timeout: 5000 });
  await d.screenshot({ path: `${out}/16-desktop-cover.png` });
  await dctx.close();
});

// 6. Site pages (src/site): prerendered HTML that reads without script, in the sitemap
const appPaths = ['/', '/privacy', '/support'];
let sitePaths = [];
await step('sitemap and robots.txt', async () => {
  const xml = await (await fetch(`${base}/sitemap.xml`)).text();
  const paths = [...xml.matchAll(/<loc>https:\/\/sendoffapp\.com([^<]*)<\/loc>/g)].map((m) => m[1]);
  sitePaths = paths.filter((p) => !appPaths.includes(p));
  for (const p of [...appPaths, '/teams', '/retirement']) if (!paths.includes(p)) throw new Error(`${p} not in the sitemap`);
  if (paths.some((p) => p.startsWith('/s/'))) throw new Error('a private link is in the sitemap');
  const robots = await (await fetch(`${base}/robots.txt`)).text();
  if (!robots.includes('Disallow: /s/') || !robots.includes('Sitemap: https://sendoffapp.com/sitemap.xml')) throw new Error(robots);
});
await step('site pages arrive as complete HTML', async () => {
  const titles = new Set();
  const descriptions = new Set();
  for (const p of sitePaths) {
    const res = await fetch(base + p);
    const html = await res.text();
    const need = (cond, what) => { if (!cond) throw new Error(`${p}: ${what}`); };
    need(res.ok && res.headers.get('content-type')?.includes('text/html'), `status ${res.status}`);
    need((html.match(/<h1[\s>]/g) ?? []).length === 1, 'one h1');
    need(!/<script[^>]*\bsrc=/.test(html), 'no script needed');
    const title = html.match(/<title>([^<]+)<\/title>/)?.[1];
    const description = html.match(/<meta name="description" content="([^"]+)"/)?.[1];
    need(title && !titles.has(title), `unique title: ${title}`);
    need(description && !descriptions.has(description) && description.length <= 160, `unique description under 160: ${description}`);
    titles.add(title);
    descriptions.add(description);
    need(html.includes(`<link rel="canonical" href="https://sendoffapp.com${p}">`), 'canonical');
    need(html.includes(`<meta property="og:url" content="https://sendoffapp.com${p}">`), 'og:url');
    const ld = JSON.parse(html.match(/<script type="application\/ld\+json">(.+?)<\/script>/)[1]);
    const types = ld['@graph'].map((n) => n['@type']);
    for (const t of ['Organization', 'MobileApplication', 'FAQPage']) need(types.includes(t), `JSON-LD ${t}`);
    const css = html.match(/<link rel="stylesheet" href="([^"]+)">/)[1];
    need((await fetch(base + css)).ok, `stylesheet ${css}`);
  }
});
await step('teams page: plans and a way to reach us', async () => {
  await page.goto(`${base}/teams`);
  if (await page.locator('.tier').count() !== 3) throw new Error('tiers');
  const href = await page.locator('.intro a.btn').getAttribute('href');
  if (!href?.startsWith('mailto:support@sendoffapp.com')) throw new Error(href);
  await shot('17-teams');
  const dctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const d = await dctx.newPage();
  await d.goto(`${base}/teams`);
  await d.screenshot({ path: `${out}/18-desktop-teams.png`, fullPage: true });
  await d.goto(`${base}/retirement`);
  await d.screenshot({ path: `${out}/19-desktop-retirement.png` });
  await dctx.close();
});
await step('every page links to the site pages', async () => {
  await page.goto(`${base}/`);
  await page.waitForSelector('.site-foot');
  const hrefs = await page.locator('a').evaluateAll((as) => as.map((a) => a.getAttribute('href')));
  for (const p of sitePaths) if (!hrefs.includes(p)) throw new Error(`landing does not link to ${p}`);
  await page.goto(`${base}/retirement`);
  if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)) throw new Error('scrolls sideways at 390');
});

console.log(errors.length ? `\nPAGE ERRORS:\n${errors.join('\n')}` : '\nno page errors');
await browser.close();
server?.kill();
process.exit(failures || errors.length ? 1 : 0);
