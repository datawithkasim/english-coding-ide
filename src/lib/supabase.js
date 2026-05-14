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

// Bootstrap from app.english-coding cross-subdomain cookie (Phase 1).
// Until cookie-widen ships, fall back to ?session=<token> query param for dev.
export function bootstrapSession() {
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
