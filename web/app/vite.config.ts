import { defineConfig, type Connect, type Plugin } from 'vite';
import { fileURLToPath } from 'node:url';
import { renderAll, sitemap } from './src/site/render';

// Two kinds of page. Every public page (/, /teams, the occasions, /privacy, /support, the 404) is
// prerendered from src/site by the plugin below. Every private link (/s/{slug}[/open|/qr]) gets
// app.html and the client router takes it from there: Cloudflare does that with the rewrites in
// public/_redirects, and dev and `vite preview` with the same rewrites here. The add-yours page,
// /s/{slug}, gets add.html instead: the same app with Apple's App Clip tag, so an iPhone offers the
// App Clip there (and for that link in Messages or a QR code) but never on the recipient's page.
// See web/app/README.md.
export default defineConfig({
  appType: 'mpa',
  server: { port: 5173, host: true },
  preview: { port: 4173, host: true },
  build: {
    target: 'es2022',
    sourcemap: true,
    rollupOptions: { input: { app: fileURLToPath(new URL('./app.html', import.meta.url)) } },
  },
  plugins: [sitePages()],
});

/** The App Clip card on the add-yours page: the Clip's bundle id, and the full app's App Store id
 *  for iPhones that can't run App Clips. Safari shows it only once the App Clip is on the App Store. */
const appClipTag = '<meta name="apple-itunes-app" content="app-id=6770213680, app-clip-bundle-id=com.dahvio.sendoff.Clip, app-clip-display=card">';

/** /s/{slug} is the add-yours page; anything longer is the reveal or the QR card. */
const isAddPage = (url: string): boolean => (url.split('?')[0] ?? '').split('/').filter(Boolean).length === 2;

/** /s/... is the app, as public/_redirects has it on Cloudflare. Dev has no add.html, so it serves
 *  app.html for every private link; `vite preview` serves the built add.html like Cloudflare. */
const toApp = (built: boolean): Connect.NextHandleFunction => (req, _res, next) => {
  if (req.url?.startsWith('/s/')) req.url = built && isAddPage(req.url) ? '/add.html' : '/app.html';
  next();
};

/** Where each page lands in dist: / is index.html, the 404 is 404.html, the rest {name}.html,
 *  which Cloudflare and `vite preview` serve at /{name}. */
const fileFor = (path: string): string => path === '/' ? 'index.html' : `${path.slice(1)}.html`;

/** The public pages in src/site, prerendered so they arrive as real HTML with no script, linked to
 *  the app's own hashed stylesheet, along with sitemap.xml. Dev renders them on request, so copy
 *  edits show on reload. */
function sitePages(): Plugin {
  let demo = false;
  return {
    name: 'sendoff-site-pages',
    enforce: 'post',
    // The same rule as src/lib/config.ts: dev and the smoke test's build show the demo Sendoffs.
    configResolved(config) { demo = config.command === 'serve' || config.mode === 'demo'; },
    configureServer(server) {
      server.middlewares.use(toApp(false));
      server.middlewares.use(async (req, res, next) => {
        const path = req.url?.split('?')[0];
        try {
          const site = await server.ssrLoadModule('/src/site/render.ts') as typeof import('./src/site/render');
          if (path === '/sitemap.xml') {
            res.setHeader('Content-Type', 'application/xml');
            return res.end(site.sitemap());
          }
          const page = site.renderAll({ css: '/src/styles/sendoff.css', demo }).find((p) => p.path === path && p.path !== site.NotFoundPath);
          if (!page) return next();
          res.setHeader('Content-Type', 'text/html; charset=utf-8');
          res.end(page.html);
        } catch (e) {
          next(e);
        }
      });
    },
    configurePreviewServer(server) {
      server.middlewares.use(toApp(true));
    },
    generateBundle(_, bundle) {
      const app = bundle['app.html'];
      if (app?.type !== 'asset') return this.error('sendoff-site-pages: no app.html in the build');
      const shell = String(app.source);
      if (!shell.includes('<title>')) return this.error('sendoff-site-pages: app.html has no <title> to put the App Clip tag before');
      this.emitFile({ type: 'asset', fileName: 'add.html', source: shell.replace('<title>', `${appClipTag}\n<title>`) });
      const entry = Object.values(bundle).find((c) => c.type === 'chunk' && c.isEntry);
      const css = entry?.type === 'chunk' ? [...(entry.viteMetadata?.importedCss ?? [])][0] : undefined;
      if (!css) return this.error('sendoff-site-pages: no stylesheet in the build to link the pages to');
      for (const page of renderAll({ css: `/${css}`, demo })) {
        this.emitFile({ type: 'asset', fileName: fileFor(page.path), source: page.html });
      }
      this.emitFile({ type: 'asset', fileName: 'sitemap.xml', source: sitemap() });
    },
  };
}

