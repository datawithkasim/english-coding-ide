import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Vite auto-adds `crossorigin` to <script type="module"> and <link rel=
// "stylesheet"> tags in the emitted index.html. That breaks inside the
// sandboxed null-origin iframe at app.english-coding.co.uk/Lab — the
// browser switches to CORS mode, sends Origin: null, and the static host
// doesn't return Access-Control-Allow-Origin. Strip the attribute so the
// iframe uses no-CORS mode (same-domain fetch works without it).
function stripCrossorigin() {
  return {
    name: 'strip-crossorigin-from-index-html',
    enforce: 'post',
    transformIndexHtml(html) {
      return html.replace(/\s+crossorigin(="[^"]*")?/g, '');
    },
  };
}

// `base: '/lab/'` so prod assets resolve when the IDE is mounted as a nested
// iframe at https://app.english-coding.co.uk/lab/index.html. Mirrors the
// english-coding-adventures `/adventures/` pattern. Local dev still serves
// from `/` on port 5180 — only prod build uses the nested base path.
export default defineConfig(({ command }) => ({
  plugins: [react(), stripCrossorigin()],
  base: command === 'build' ? '/lab/' : '/',
  server: { port: 5180 },
}));
