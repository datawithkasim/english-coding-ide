import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!url || !key) {
  console.warn('[supabase] VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY missing');
}

export const supabase = createClient(url ?? '', key ?? '', {
  auth: { persistSession: false },  // we use app.english-coding session_token, not gotrue
});

const SESSION_KEY = 'ec_session_token';

export function getSessionToken() {
  return localStorage.getItem(SESSION_KEY);
}

export function setSessionToken(token) {
  if (token) localStorage.setItem(SESSION_KEY, token);
  else localStorage.removeItem(SESSION_KEY);
}

// Read the parent-domain `ec_session` cookie set by app.english-coding's
// storeSessionToken(). Returns undefined if not on the english-coding.co.uk
// parent domain or the cookie isn't present.
function readSessionCookie() {
  if (typeof document === 'undefined') return undefined;
  const m = document.cookie.match(/(?:^|;\s*)ec_session=([^;]+)/);
  return m ? decodeURIComponent(m[1]) : undefined;
}

// Read URL fragment `#session=<token>`. Fragments are never sent to the
// server in requests, never written to access logs, and don't appear in
// Referer headers — strictly safer than `?session=` for cross-frame auth
// handoff from the parent app at app.english-coding.co.uk/Lab.
function readSessionFragment() {
  if (typeof window === 'undefined') return undefined;
  const hash = window.location.hash || '';
  const m = hash.match(/(?:^#|&)session=([^&]+)/);
  return m ? decodeURIComponent(m[1]) : undefined;
}

// Bootstrap order:
//   1. URL fragment `#session=<token>` — primary path when nested in the
//      app's sandboxed iframe at /lab/. Cleaned from URL via replaceState.
//   2. `ec_session` cookie if app ever re-enables parent-domain cookies
//      (currently host-only, so this is mostly inert on the lab origin).
//   3. `?session=<token>` query param — local dev fallback. Cleaned too.
export function bootstrapSession() {
  const fromFragment = readSessionFragment();
  if (fromFragment) {
    setSessionToken(fromFragment);
    // Strip the session fragment but preserve any other hash routing data.
    const remaining = window.location.hash
      .replace(/(?:^#|&)session=[^&]+/, '')
      .replace(/^&/, '#');
    const clean = window.location.pathname + window.location.search +
      (remaining && remaining !== '#' ? remaining : '');
    window.history.replaceState({}, '', clean);
    return fromFragment;
  }
  const fromCookie = readSessionCookie();
  if (fromCookie) {
    setSessionToken(fromCookie);
    return fromCookie;
  }
  const params = new URLSearchParams(window.location.search);
  const fromUrl = params.get('session');
  if (fromUrl) {
    setSessionToken(fromUrl);
    params.delete('session');
    const clean = window.location.pathname + (params.toString() ? `?${params}` : '');
    window.history.replaceState({}, '', clean);
  }
  return getSessionToken();
}
