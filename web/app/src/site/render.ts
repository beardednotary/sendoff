import { Icons } from '../lib/dom';
import { occasionTitle } from '../lib/themes';
import {
  Site, Steps, Entries, Screens, CommonFaq, OccasionPages, TeamsPage, Tiers, TeamIncludes, TeamFaq, PersonalPrices,
  PublicPaths, FooterLinks, promptsFor, type Cover, type Faq, type OccasionPage, type Screen,
} from './content';

// The public pages as HTML strings, in the Evening language of the landing page. Called at build
// time by the sitePages plugin (vite.config.ts); nothing here runs in the browser.

export interface Rendered { path: string; html: string }

/** Where the shared stylesheet lives: the hashed file in a build, the source in dev. */
export interface Assets { css: string }

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const url = (path: string): string => Site.origin + path;

const icon = (name: keyof typeof Icons): string => Icons[name].replace('<svg', '<svg aria-hidden="true"');

export function renderAll(assets: Assets): Rendered[] {
  return [
    { path: TeamsPage.path, html: teamsPage(assets) },
    ...OccasionPages.map((p) => ({ path: p.path, html: occasionPage(p, assets) })),
  ];
}

export function sitemap(): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${PublicPaths.map((p) => `  <url><loc>${url(p)}</loc></url>`).join('\n')}
</urlset>
`;
}

// Structured data -----------------------------------------------------------------------------

const org = {
  '@type': 'Organization',
  '@id': `${Site.origin}/#org`,
  name: 'Sendoff',
  url: `${Site.origin}/`,
  logo: `${Site.origin}/apple-touch-icon.png`,
  email: Site.email,
  contactPoint: { '@type': 'ContactPoint', contactType: 'customer support', email: Site.email },
};

const app = {
  '@type': 'MobileApplication',
  '@id': `${Site.origin}/#app`,
  name: Site.appName,
  alternateName: 'Sendoff',
  operatingSystem: 'iOS',
  applicationCategory: 'LifestyleApplication',
  description: 'A sealed group keepsake for retirements, graduations and goodbyes. Everyone adds a note, photos, a voice note or a video privately; one person opens it, on the day.',
  publisher: { '@id': `${Site.origin}/#org` },
  offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
  ...(Site.appStoreUrl ? { url: Site.appStoreUrl, downloadUrl: Site.appStoreUrl } : {}),
};

/** Organization, the app and this page, plus its questions when it has them. Also used for the
 *  landing page's index.html. */
export function jsonLd(page?: { path: string; title: string; description: string; faq?: Faq[] }): string {
  const graph: object[] = [org, app, { '@type': 'WebSite', '@id': `${Site.origin}/#site`, name: 'Sendoff', url: `${Site.origin}/`, publisher: { '@id': `${Site.origin}/#org` } }];
  if (page) {
    graph.push({
      '@type': page.faq?.length ? 'FAQPage' : 'WebPage',
      '@id': url(page.path),
      url: url(page.path),
      name: page.title,
      description: page.description,
      isPartOf: { '@id': `${Site.origin}/#site` },
      about: { '@id': `${Site.origin}/#app` },
      ...(page.faq?.length ? {
        mainEntity: page.faq.map((f) => ({ '@type': 'Question', name: f.q, acceptedAnswer: { '@type': 'Answer', text: f.a } })),
      } : {}),
    });
  }
  // `<` can never close the script element early.
  return `<script type="application/ld+json">${JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replace(/</g, '\\u003c')}</script>`;
}

// Page shell ----------------------------------------------------------------------------------

function shell(page: { path: string; title: string; description: string; faq?: Faq[] }, assets: Assets, body: string): string {
  return `<!doctype html>
<html lang="en" data-theme="auto">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#F5F3EF" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0E0E0D" media="(prefers-color-scheme: dark)">
<title>${esc(page.title)}</title>
<meta name="description" content="${esc(page.description)}">
<link rel="canonical" href="${url(page.path)}">
<meta property="og:site_name" content="Sendoff">
<meta property="og:type" content="website">
<meta property="og:url" content="${url(page.path)}">
<meta property="og:title" content="${esc(page.title)}">
<meta property="og:description" content="${esc(page.description)}">
<meta property="og:image" content="${Site.origin}/og.png">
<meta property="og:image:width" content="600">
<meta property="og:image:height" content="600">
<meta property="og:image:alt" content="Sendoff">
<meta name="twitter:card" content="summary">
${Site.appStoreId ? `<meta name="apple-itunes-app" content="app-id=${esc(Site.appStoreId)}">\n` : ''}<link rel="icon" type="image/svg+xml" href="/pathmark.svg">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" href="/fonts/newsreader-latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="${esc(assets.css)}">
${jsonLd(page)}
</head>
<body>
${header(page.path)}
<main class="site">
${body}
</main>
${footer()}
</body>
</html>
`;
}

function header(path: string): string {
  const current = path === TeamsPage.path ? ' aria-current="page"' : '';
  return `<header class="site-head">
  <a href="/" aria-label="Sendoff home">${Icons.pathmark}</a>
  <nav class="site-nav" aria-label="Sendoff"><a href="${TeamsPage.path}"${current}>${TeamsPage.label}</a></nav>
</header>`;
}

function footer(): string {
  const links = (l: { href: string; label: string }[]) => l.map((a) => `<li><a href="${a.href}">${esc(a.label)}</a></li>`).join('');
  return `<footer class="site-foot caption">
  <nav aria-label="Occasions"><ul>${links(FooterLinks.occasions)}</ul></nav>
  <nav aria-label="More"><ul>${links(FooterLinks.more)}</ul></nav>
  <p>© ${new Date().getFullYear()} Sendoff</p>
</footer>`;
}

// Pieces --------------------------------------------------------------------------------------

/** The App Store call to action, or "coming soon" until the app is live. */
function getTheApp(): string {
  const action = Site.appStoreUrl
    ? `<p><a class="btn primary" href="${esc(Site.appStoreUrl)}">Get Sendoff on the App Store</a></p>`
    : '<p class="ui">Coming soon to the App Store.</p>';
  return `<div class="cta">${action}<p class="caption">Organizers start one in the iPhone app. Everyone else just needs the link.</p></div>`;
}

/** A ruled section: its heading beside the content, or above it when `wide` (for rows of screens). */
function section(eyebrow: string, title: string, content: string, id?: string, wide = false): string {
  return `<section class="sect${wide ? ' wide' : ''}"${id ? ` id="${id}"` : ''}>
  <header><p class="eyebrow">${esc(eyebrow)}</p><h2 class="title">${esc(title)}</h2></header>
  <div>${content}</div>
</section>`;
}

const prose = (paragraphs: string[]): string => `<div class="prose">${paragraphs.map((p) => `<p>${esc(p)}</p>`).join('')}</div>`;

/** Each picture's full size, and the width it is shown at (for `sizes`). */
const PHOTO = { w: 640, h: 800, sizes: '300px' };
const SCREEN = { w: 480, h: 1044, sizes: '(min-width: 800px) 22vw, min(62vw, 240px)' };

/** An image from public/site: AVIF at half and full width ({name}-{width}.avif), with a full-width
 *  JPEG for browsers without AVIF. Only the cover loads up front. */
function picture(path: string, alt: string, { w, h, sizes }: typeof PHOTO, first = false): string {
  const at = (width: number, type: string) => `/site/${path}-${width}.${type}`;
  return `<picture><source type="image/avif" srcset="${at(w / 2, 'avif')} ${w / 2}w, ${at(w, 'avif')} ${w}w" sizes="${sizes}">`
    + `<img src="${at(w, 'jpg')}" alt="${esc(alt)}" width="${w}" height="${h}" ${first ? 'fetchpriority="high"' : 'loading="lazy"'} decoding="async"></picture>`;
}

/** The cover as the app draws it once the seal opens: their photo fading into the page, the
 *  occasion, their name, and the line from whoever started it. */
function coverScreen(c: Cover, eyebrow: string): string {
  return `<figure class="screen cover-screen${c.mark ? ' marked' : ''}">
  ${picture(`photos/${c.photo}`, c.alt, PHOTO, true)}
  ${c.mark ? `<p class="mark">${esc(c.mark)}</p>` : ''}
  <figcaption>
    <p class="eyebrow">${esc(eyebrow)}</p>
    <p class="who">${esc(c.name)}</p>
    <p class="from">${esc(c.from)}</p>
    <p class="message">${esc(c.message)}</p>
    <p class="begin" aria-hidden="true">Begin ${icon('arrow')}</p>
  </figcaption>
</figure>`;
}

/** App screens in a row, each with its words: a strip to swipe on a phone, a grid on a desktop. */
function reel(label: string, items: [name: string, detail: string, screen: Screen][], numbered: boolean): string {
  const list = numbered ? 'ol' : 'ul';
  return `<div class="reel" role="region" aria-label="${esc(label)}" tabindex="0"><${list}>${items.map(([name, detail, screen], i) => `
    <li><figure class="screen">${picture(`app/${screen}`, Screens[screen], SCREEN)}</figure>
      <div><h3 class="name">${numbered ? `<span class="n" aria-hidden="true">${i + 1}</span>` : ''}${esc(name)}</h3><p>${esc(detail)}</p></div></li>`).join('')}
  </${list}></div>`;
}

function intro(eyebrow: string, headline: [string, string], lede: string, action: string, card: string): string {
  return `<section class="intro">
  <div class="lead">
    <p class="eyebrow">${esc(eyebrow)}</p>
    <h1 class="display xl">${esc(headline[0])}<br> ${esc(headline[1])}</h1>
    <p class="lede">${esc(lede)}</p>
    ${action}
  </div>
  ${card}
</section>`;
}

function faqList(faq: Faq[]): string {
  return `<div class="faq">${faq.map((f) => `<div><h3 class="name">${esc(f.q)}</h3><p>${esc(f.a)}</p></div>`).join('')}</div>`;
}

// Occasion pages ------------------------------------------------------------------------------

function occasionPage(p: OccasionPage, assets: Assets): string {
  const faq = [p.faq, ...CommonFaq];
  const prompts = `<div class="prose"><p>Anyone stuck on where to start gets a few prompts, written for the occasion.</p></div>
    <ul class="prompts">${promptsFor(p.occasion).map((t) => `<li>${esc(t)}</li>`).join('')}</ul>`;
  const cost = `<div class="prose">
    <p>Starting one and collecting up to 10 entries is free. When more people want in, the organizer pays once for that Sendoff: $8.99 for up to 100 entries, or $14.99 for no limit and every paid look. Nobody who adds to it or opens it pays.</p>
    <p>Running these for a whole company or school? <a href="${TeamsPage.path}">Sendoff for teams</a> covers every one for a year.</p>
  </div>`;

  return shell({ ...p, faq }, assets, [
    intro(p.eyebrow, p.headline, p.lede, getTheApp(), coverScreen(p.cover, occasionTitle(p.occasion))),
    section('How it works', 'Four steps, one link.', reel('How it works, in the app', Steps, true), undefined, true),
    section('What goes in', 'More than a signature.', reel('Entries as they open', Entries, false), undefined, true),
    ...p.story.map((s) => section(p.eyebrow, s.heading, prose(s.paragraphs))),
    section('Prompts', 'Something to start from.', prompts),
    section('Cost', 'Free to start.', cost),
    section('Questions', 'Before you start.', faqList(faq)),
    `<section class="closing">
  <h2 class="display">Everyone adds privately.<br> One person opens it, on the day.</h2>
  ${getTheApp()}
</section>`,
  ].join('\n'));
}

// Teams ---------------------------------------------------------------------------------------

function teamsPage(assets: Assets): string {
  const mail = (subject: string) => `mailto:${Site.email}?subject=${encodeURIComponent(subject)}`;
  const talk = `<div class="cta">
    <p><a class="btn primary" href="${mail('Sendoff for teams')}">Talk to us</a></p>
    <p class="caption">Or write to <a href="mailto:${Site.email}">${Site.email}</a>. A person reads every message.</p>
  </div>`;

  const tiers = `<div class="tiers">${Tiers.map((t) => {
    const button = t.checkout
      ? `<a class="btn primary wide" href="${esc(t.checkout)}">Buy ${esc(t.name)}</a>`
      : `<a class="btn wide" href="${mail(`Sendoff for teams: ${t.name}`)}">Talk to us</a>`;
    return `<div class="tier">
      <h3 class="eyebrow">${esc(t.name)}</h3>
      <p class="amount">${esc(t.price)}${t.per ? ` <span>${esc(t.per)}</span>` : ''}</p>
      <p class="size">${esc(t.size)}</p>
      <p class="caption">${esc(t.detail)}</p>
      ${button}
    </div>`;
  }).join('')}</div>
  <p class="caption tier-note">“People” means the people on your roster, who can start a Sendoff. Everyone who adds to one, and everyone it is for, is free and never counted. Prices in US dollars, billed yearly.</p>`;

  const includes = `<ul class="includes">${TeamIncludes.map(([name, detail]) =>
    `<li><h3 class="name">${esc(name)}</h3><p>${esc(detail)}</p></li>`).join('')}</ul>`;

  const personal = `<div class="prose"><p>One farewell, one organizer: buy it in the iPhone app instead. Paid once per Sendoff; nobody who adds to it or opens it pays.</p></div>
  <dl class="prices">${PersonalPrices.map((r) =>
    `<div><dt class="name">${esc(r.name)}</dt><dd class="amount">${esc(r.price)}</dd><dd class="caption">${esc(r.detail)}</dd></div>`).join('')}</dl>
  <p class="caption">US prices; the App Store shows yours.</p>`;

  return shell({ ...TeamsPage, faq: TeamFaq }, assets, [
    intro('Sendoff for teams', ['For the people who', 'organize every goodbye.'],
      'Companies, schools and teams run dozens of farewells a year. One annual plan lets anyone on your roster start a Sendoff at the Plus level, with your logo on the cover and one invoice for the year.',
      talk, coverScreen({ ...OccasionPages[0]!.cover, mark: 'Halden & Co.' }, occasionTitle('retirement'))),
    section('Plans', 'Priced by the size of your team.', tiers, 'plans'),
    section('Every plan', 'What’s included.', includes),
    section('Who it’s for', 'Wherever people leave.', prose([
      'People and HR teams who mark every retirement and every last day. Schools and districts saying goodbye to teachers each June. Clubs, units and teams who send someone off every season.',
      'The sealed, private envelope matters more at work than anywhere: people write what they mean when they know only one person will read it.',
    ])),
    section('Just one?', 'Personal prices.', personal, 'personal'),
    section('Questions', 'Before you write to us.', faqList(TeamFaq)),
    `<section class="closing">
  <h2 class="display">Every goodbye at work,<br> handled the same way.</h2>
  ${talk}
</section>`,
  ].join('\n'));
}
