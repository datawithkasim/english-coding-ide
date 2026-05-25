import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// `base: '/lab/'` so prod assets resolve when the IDE is mounted as a nested
// iframe at https://app.english-coding.co.uk/lab/index.html. Mirrors the
// english-coding-adventures `/adventures/` pattern. Local dev still serves
// from `/` on port 5180 — only prod build uses the nested base path.
export default defineConfig(({ command }) => ({
  plugins: [react()],
  base: command === 'build' ? '/lab/' : '/',
  server: { port: 5180 },
}));
