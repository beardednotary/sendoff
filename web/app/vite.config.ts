import { defineConfig, type Plugin } from 'vite';
import { renderAll, sitemap, jsonLd } from './src/site/render';

// Single-page app. Every /s/{slug}[/open|/qr] path serves index.html and the client router
// takes it from there. Production (Cloudflare, wrangler.jsonc) does the same with its
// single-page-application fallback; see web/app/README.md.
export default defineConfig({
  appType: 'spa',
  server: { port: 5173, host: true },
  preview: { port: 4173, host: true },
  build: { target: 'es2022', sourcemap: true },
  plugins: [sitePages()],
});

/** The public pages in src/site (/teams and one per occasion), prerendered so they arrive as
 *  real HTML with no script. The build writes each to dist/{name}.html, which Cloudflare and
 *  `vite preview` both serve at /{name}, linked to the app's own hashed stylesheet; it also
 *  writes sitemap.xml. Dev renders them on request, so copy edits show on reload. */
function sitePages(): Plugin {
  return {
    name: 'sendoff-site-pages',
    enforce: 'post',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const path = req.url?.split('?')[0];
        try {
          const site = await server.ssrLoadModule('/src/site/render.ts') as typeof import('./src/site/render');
          if (path === '/sitemap.xml') {
            res.setHeader('Content-Type', 'application/xml');
            return res.end(site.sitemap());
          }
          const page = site.renderAll({ css: '/src/styles/sendoff.css' }).find((p) => p.path === path);
          if (!page) return next();
          res.setHeader('Content-Type', 'text/html; charset=utf-8');
          res.end(page.html);
        } catch (e) {
          next(e);
        }
      });
    },
    // The landing page (index.html) says who we are and what the app is, as the others do.
    transformIndexHtml(html) {
      return html.replace('</head>', `${jsonLd()}\n</head>`);
    },
    generateBundle(_, bundle) {
      const entry = Object.values(bundle).find((c) => c.type === 'chunk' && c.isEntry);
      const css = entry?.type === 'chunk' ? [...(entry.viteMetadata?.importedCss ?? [])][0] : undefined;
      if (!css) return this.error('sendoff-site-pages: no stylesheet in the build to link the pages to');
      for (const page of renderAll({ css: `/${css}` })) {
        this.emitFile({ type: 'asset', fileName: `${page.path.slice(1)}.html`, source: page.html });
      }
      this.emitFile({ type: 'asset', fileName: 'sitemap.xml', source: sitemap() });
    },
  };
}
