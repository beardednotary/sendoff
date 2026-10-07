import { defineConfig } from 'vite';

// Single-page app. Every /s/{slug}[/open|/qr] path serves index.html and the client router
// takes it from there. Production hosts (Vercel, Netlify, Cloudflare Pages) need the same
// rewrite; see web/app/README.md.
export default defineConfig({
  appType: 'spa',
  server: { port: 5173, host: true },
  preview: { port: 4173, host: true },
  build: { target: 'es2022', sourcemap: true },
});
