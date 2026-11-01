import { Icons } from '../lib/dom';
import { occasionTitle } from '../lib/themes';
import {
  Site, Steps, Entries, Screens, CommonFaq, OccasionPages, TeamsPage, Tiers, TeamIncludes, TeamFaq, PersonalPrices,
  HomePage, Benefits, PlanTeasers, HomeFaq, SongNote, PublicPaths, FooterLinks, promptsFor,
  type Cover, type Faq, type OccasionPage, type Screen,
} from './content';
import { PrivacyPage, SupportPage, InfoUpdated, type InfoPage } from './info';

// The public pages as HTML strings, in the Evening language of the app. Called at build time by
// the sitePages plugin (vite.config.ts); nothing here runs in the browser.

export interface Rendered { path: string; html: string }

export interface RenderOptions {
  /** Where the shared stylesheet lives: the hashed file in a build, the source in dev. */
  css: string;
  /** Dev and the smoke test's build: the homepage links to the mock store's demo Sendoffs. */
  demo: boolean;
}

/** The page served for any path that matches nothing (Cloudflare's 404-page handling). */
export const NotFoundPath = '/404';

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const url = (path: string): string => Site.origin + path;

const icon = (name: keyof typeof Icons): string => Icons[name].replace('<svg', '<svg aria-hidden="true"');

export function renderAll(o: RenderOptions): Rendered[] {
  return [
    { path: HomePage.path, html: homePage(o) },
    { path: TeamsPage.path, html: teamsPage(o) },
    ...OccasionPages.map((p) => ({ path: p.path, html: occasionPage(p, o) })),
    ...[PrivacyPage, SupportPage].map((p) => ({ path: p.path, html: infoPage(p, o) })),
    { path: NotFoundPath, html: notFoundPage(o) },
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

interface PageMeta { path: string; title: string; description: string; faq?: Faq[] }

/** Organization, the app and this page, plus its questions when it has them. */
function jsonLd(page: PageMeta): string {
  const graph: object[] = [org, app, { '@type': 'WebSite', '@id': `${Site.origin}/#site`, name: 'Sendoff', url: `${Site.origin}/`, publisher: { '@id': `${Site.origin}/#org` } }];
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
  // `<` can never close the script element early.
  return `<script type="application/ld+json">${JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replace(/</g, '\\u003c')}</script>`;
}

// Page shell ----------------------------------------------------------------------------------

/** A whole page. `top` replaces the plain header (the homepage puts it inside its hero); a
 *  `noindex` page has no canonical URL, link-preview tags or structured data. */
function shell(page: PageMeta, o: RenderOptions, body: string, opts: { top?: string; noindex?: boolean } = {}): string {
  const indexed = !opts.noindex;
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
${indexed ? `<link rel="canonical" href="${url(page.path)}">
<meta property="og:site_name" content="Sendoff">
<meta property="og:type" content="website">
<meta property="og:url" content="${url(page.path)}">
<meta property="og:title" content="${esc(page.title)}">
<meta property="og:description" content="${esc(page.description)}">
<meta property="og:image" content="${Site.origin}/og.png">
<meta property="og:image:width" content="600">
<meta property="og:image:height" content="600">
<meta property="og:image:alt" content="Sendoff">
<meta name="twitter:card" content="summary">` : '<meta name="robots" content="noindex">'}
${Site.appStoreId ? `<meta name="apple-itunes-app" content="app-id=${esc(Site.appStoreId)}">\n` : ''}<link rel="icon" type="image/svg+xml" href="/pathmark.svg">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" href="/fonts/newsreader-latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="${esc(o.css)}">
${indexed ? jsonLd(page) : ''}
</head>
<body>
${opts.top ?? header(page.path)}
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
const SCREEN = { w: 480, h: 1044, sizes: '(min-width: 1120px) 216px, (min-width: 800px) 20vw, (min-width: 560px) 260px, min(68vw, 260px)' };

/** An image from public/site: AVIF at half and full width ({name}-{width}.avif), with a full-width
 *  JPEG for browsers without AVIF. Pictures below the fold wait until they are near. */
function picture(path: string, alt: string, { w, h, sizes }: typeof PHOTO, load: 'first' | 'eager' | 'lazy' = 'lazy'): string {
  const at = (width: number, type: string) => `/site/${path}-${width}.${type}`;
  const how = { first: 'fetchpriority="high"', eager: '', lazy: 'loading="lazy"' }[load];
  return `<picture><source type="image/avif" srcset="${at(w / 2, 'avif')} ${w / 2}w, ${at(w, 'avif')} ${w}w" sizes="${sizes}">`
    + `<img src="${at(w, 'jpg')}" alt="${esc(alt)}" width="${w}" height="${h}"${how ? ` ${how}` : ''} decoding="async"></picture>`;
}

/** The cover as the app draws it once the seal opens: their photo fading into the page, the
 *  occasion, their name, and the line from whoever started it. */
function coverScreen(c: Cover, eyebrow: string, sizes = PHOTO.sizes): string {
  return `<figure class="screen cover-screen${c.mark ? ' marked' : ''}">
  ${picture(`photos/${c.photo}`, c.alt, { ...PHOTO, sizes }, 'first')}
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

/** App screens, each with its words: one above the next on a phone, a row on a desktop. */
function screenList(items: [name: string, detail: string, screen: Screen][], numbered: boolean): string {
  const list = numbered ? 'ol' : 'ul';
  return `<${list} class="screens">${items.map(([name, detail, screen], i) => `
    <li><figure class="screen">${picture(`app/${screen}`, Screens[screen], SCREEN)}</figure>
      <div><h3 class="name">${numbered ? `<span class="n" aria-hidden="true">${i + 1}</span>` : ''}${esc(name)}</h3><p>${esc(detail)}</p></div></li>`).join('')}
  </${list}>`;
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

const closing = (headline: string, action: string): string => `<section class="closing">
  <h2 class="display">${headline}</h2>
  ${action}
</section>`;

// Home ----------------------------------------------------------------------------------------

function homePage(o: RenderOptions): string {
  const maria = OccasionPages[0]!.cover;
  // The sealed screen, the cover and a photo entry: the moment it opens, left to right.
  const trio = `<div class="trio">
    <figure class="screen side">${picture('app/sealed', Screens.sealed, { ...SCREEN, sizes: '(min-width: 800px) 220px, 28vw' }, 'eager')}</figure>
    ${coverScreen(maria, occasionTitle('retirement'), '(min-width: 800px) 300px, 39vw')}
    <figure class="screen side">${picture('app/photo', Screens.photo, { ...SCREEN, sizes: '(min-width: 800px) 220px, 28vw' }, 'eager')}</figure>
  </div>`;
  const top = `<div class="hero-band">
${header(HomePage.path)}
<section class="home-hero">
  <div class="lead">
    <p class="eyebrow">Sendoff</p>
    <h1 class="display mega">Everyone adds privately.<br> One person opens it, on the day.</h1>
    <p class="lede">A sealed group keepsake for retirements, graduations and goodbyes. Notes, photos, voice notes and video from everyone, kept private until the day, then theirs to keep.</p>
    <div class="actions">
      <a class="btn primary" href="#how">See how it works</a>
      <a class="btn" href="${TeamsPage.path}">For teams</a>
    </div>
    <p class="caption">${Site.appStoreUrl ? `<a href="${esc(Site.appStoreUrl)}">Get Sendoff on the App Store</a>.` : 'Coming soon to the App Store.'} Organizers start one in the iPhone app; everyone else just needs the link.</p>
  </div>
  ${trio}
</section>
</div>
<nav class="jump" aria-label="On this page"><ul>
  ${[['#how', 'How it works'], ['#why', 'Why Sendoff'], ['#inside', 'What goes in'], ['#occasions', 'Occasions'], ['#pricing', 'Pricing'], ['#questions', 'Questions']]
    .map(([href, label]) => `<li><a href="${href}">${label}</a></li>`).join('')}
</ul></nav>`;

  const benefits = `<ul class="benefits">${Benefits.map(([i, name, detail]) =>
    `<li><span class="glyph">${icon(i)}</span><h3 class="name">${esc(name)}</h3><p>${esc(detail)}</p></li>`).join('')}</ul>`;

  const occasions = `<ul class="occasions">${OccasionPages.map((p) => `
    <li><a class="occasion-card" href="${p.path}">${picture(`photos/${p.cover.photo}`, p.cover.alt, { ...PHOTO, sizes: '(min-width: 1120px) 310px, (min-width: 800px) 30vw, 46vw' })}
      <span class="eyebrow">${esc(occasionTitle(p.occasion))}</span><span class="line">${esc(p.teaser)}</span></a></li>`).join('')}
  </ul>`;

  const pricing = `<div class="tiers">${PlanTeasers.map((t) => `<div class="tier">
      <h3 class="eyebrow">${esc(t.name)}</h3>
      <p class="amount">${esc(t.price)}${t.per ? ` <span>${esc(t.per)}</span>` : ''}</p>
      <p class="size">${esc(t.size)}</p>
      <p class="caption">${esc(t.detail)}</p>
    </div>`).join('')}</div>
  <div class="prose pricing-notes">
    <p>Paid once per Sendoff, by the organizer, in the app. Nobody who adds to it or opens it pays. Packs of five ($34.99) and ten ($59.99), and Plus looks on their own ($4.99), are in the app too, and every plan can be printed or saved as a PDF.</p>
    <p>Running these for a company or school? <a href="${TeamsPage.path}">Sendoff for teams</a> covers every one for a year, from $169.</p>
  </div>
  <p class="caption">${esc(SongNote)} US prices; the App Store shows yours.</p>`;

  const demo = o.demo ? `<section class="sect wide">
  <header><p class="eyebrow">Demo, no backend configured</p></header>
  <div class="demo-links">
    <a href="/s/maria-r/open?k=demo"><span class="name">Maria Reyes</span><span class="caption">The reveal</span></a>
    <a href="/s/mr-patel/open?k=demo"><span class="name">Mr. Patel</span><span class="caption">Sealed, counting down</span></a>
    <a href="/s/jo-moves?t=demo"><span class="name">Jo Lindqvist</span><span class="caption">Add yours</span></a>
    <a href="/s/jo-moves/qr?t=demo"><span class="name">Jo Lindqvist</span><span class="caption">QR card</span></a>
  </div>
</section>` : '';

  return shell({ ...HomePage, faq: HomeFaq }, o, [
    demo,
    section('How it works', 'Four steps, one link.', screenList(Steps, true), 'how', true),
    section('Why Sendoff', 'A sealed envelope, not a board.', benefits, 'why', true),
    section('What goes in', 'More than a signature.', screenList(Entries, false), 'inside', true),
    section('Occasions', 'For whoever is leaving.', occasions, 'occasions', true),
    section('Pricing', 'Free to start.', pricing, 'pricing', true),
    section('Questions', 'Before you start.', faqList(HomeFaq), 'questions'),
    closing('Collect the words people<br> never get around to saying.', getTheApp()),
  ].join('\n'), { top });
}

// Occasion pages ------------------------------------------------------------------------------

function occasionPage(p: OccasionPage, o: RenderOptions): string {
  const faq = [p.faq, ...CommonFaq];
  const prompts = `<div class="prose"><p>Anyone stuck on where to start gets a few prompts, written for the occasion.</p></div>
    <ul class="prompts">${promptsFor(p.occasion).map((t) => `<li>${esc(t)}</li>`).join('')}</ul>`;
  const cost = `<div class="prose">
    <p>Starting one and collecting up to 10 entries is free. When more people want in, the organizer pays once for that Sendoff: $8.99 for up to 100 entries, or $14.99 for no limit, every Plus look and a song from Apple Music. Nobody who adds to it or opens it pays, and every plan can be printed or saved as a PDF.</p>
    <p>Running these for a whole company or school? <a href="${TeamsPage.path}">Sendoff for teams</a> covers every one for a year.</p>
  </div>
  <p class="caption cost-note">${esc(SongNote)}</p>`;

  return shell({ ...p, faq }, o, [
    intro(p.eyebrow, p.headline, p.lede, getTheApp(), coverScreen(p.cover, occasionTitle(p.occasion))),
    section('How it works', 'Four steps, one link.', screenList(Steps, true), undefined, true),
    section('What goes in', 'More than a signature.', screenList(Entries, false), undefined, true),
    ...p.story.map((s) => section(p.eyebrow, s.heading, prose(s.paragraphs))),
    section('Prompts', 'Something to start from.', prompts),
    section('Cost', 'Free to start.', cost),
    section('Questions', 'Before you start.', faqList(faq)),
    closing('Everyone adds privately.<br> One person opens it, on the day.', getTheApp()),
  ].join('\n'));
}

// Teams ---------------------------------------------------------------------------------------

function teamsPage(o: RenderOptions): string {
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

  const personal = `<div class="prose"><p>One farewell, one organizer: buy it in the iPhone app instead. Paid once per Sendoff; nobody who adds to it or opens it pays. Every plan can be printed or saved as a PDF.</p></div>
  <dl class="prices">${PersonalPrices.map((r) =>
    `<div><dt class="name">${esc(r.name)}</dt><dd class="amount">${esc(r.price)}</dd><dd class="caption">${esc(r.detail)}</dd></div>`).join('')}</dl>
  <p class="caption">${esc(SongNote)} US prices; the App Store shows yours.</p>`;

  return shell({ ...TeamsPage, faq: TeamFaq }, o, [
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
    closing('Every goodbye at work,<br> handled the same way.', talk),
  ].join('\n'));
}

// Privacy, support and not found --------------------------------------------------------------

function infoPage(p: InfoPage, o: RenderOptions): string {
  const blocks = p.blocks.map((b) => typeof b === 'string'
    ? `<p>${esc(b)}</p>`
    : `<section><h2 class="name">${esc(b[0])}</h2>${b.slice(1).map((t) => `<p>${esc(t)}</p>`).join('')}</section>`).join('\n');
  return shell(p, o, `<article class="doc">
  <p class="eyebrow">Updated ${InfoUpdated}</p>
  <h1 class="display">${esc(p.title.split(' · ')[0]!)}</h1>
  <p class="lede">${esc(p.lead)}</p>
  ${blocks}
  <p>Questions: <a href="mailto:${Site.email}">${Site.email}</a>.</p>
</article>`);
}

function notFoundPage(o: RenderOptions): string {
  return shell({ path: NotFoundPath, title: 'Nothing here · Sendoff', description: 'This page does not exist.' }, o, `<section class="doc lost">
  <p class="eyebrow">Not found</p>
  <h1 class="display">Nothing here.</h1>
  <p class="lede">The page may have moved. If someone sent you a link to a Sendoff, check you have all of it, including everything after the question mark.</p>
  <p><a class="btn primary" href="/">What is Sendoff?</a></p>
</section>`, { noindex: true });
}
