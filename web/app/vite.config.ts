import { defineConfig, type Connect, type Plugin } from 'vite';
import { fileURLToPath } from 'node:url';
import { renderAll, sitemap } from './src/site/render';

// Two kinds of page. Every public page (/, /teams, the occasions, /privacy, /support, the 404) is
// prerendered from src/site by the plugin below. Every private link (/s/{slug}[/open|/qr]) gets
// app.html and the client router takes it from there: Cloudflare does that with the rewrite in
// public/_redirects, and dev and `vite preview` with the same rewrite here. See web/app/README.md.
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

/** /s/... is the app, as public/_redirects has it on Cloudflare. */
const toApp: Connect.NextHandleFunction = (req, _res, next) => {
  if (req.url?.startsWith('/s/')) req.url = '/app.html';
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
      server.middlewares.use(toApp);
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
      server.middlewares.use(toApp);
    },
    generateBundle(_, bundle) {
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

