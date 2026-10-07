import './styles/sendoff.css';
import { contributePage } from './pages/contribute';
import { openPage } from './pages/open';
import { qrPage } from './pages/qr';
import { landingPage } from './pages/landing';
import { errorView } from './pages/shared';
import { mount } from './lib/dom';

// Routes (see docs/ARCHITECTURE.md, Web):
//   /                      landing
//   /s/{slug}?t=token      contribute
//   /s/{slug}/open?k=key   the reveal
//   /s/{slug}/qr?t=token   printable QR card

async function route(): Promise<void> {
  const parts = location.pathname.split('/').filter(Boolean);
  const q = new URLSearchParams(location.search);
  try {
    if (parts.length === 0) return await landingPage();
    if (parts[0] === 's' && parts[1]) {
      const slug = decodeURIComponent(parts[1]);
      const tail = parts[2];
      if (!tail) return await contributePage(slug, q.get('t'));
      if (tail === 'open') return await openPage(slug, q.get('k'));
      if (tail === 'qr') return await qrPage(slug, q.get('t'));
    }
    mount(errorView('Nothing here.', 'Check the link you were sent.'));
  } catch (e) {
    console.error(e);
    mount(errorView('Something went wrong.', "Reload the page. If it keeps happening, the link may have expired."));
  }
}

window.addEventListener('popstate', () => void route());
void route();
