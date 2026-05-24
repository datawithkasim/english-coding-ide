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

// Bootstrap order: parent-domain cookie (set by app.english-coding after login)
// first, then ?session=<token> URL param as a dev-only fallback for local
// testing (localhost has no shared cookie path with app.english-coding.co.uk).
// The URL value is cleaned from the address bar immediately so it doesn't
// linger in history.
export function bootstrapSession() {
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
