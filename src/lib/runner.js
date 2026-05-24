// Run-project client. POSTs the workspace to the droplet's /run_project
// endpoint, then records the result via ide_record_run.
//
// This is the one-shot version (HTTP request → final stdout). WSS streaming
// is a Phase 3.5 polish — same record_run row shape.

import { supabase, getSessionToken } from './supabase.js';

const EXECUTOR_URL = import.meta.env.VITE_CODE_EXECUTOR_URL;

export async function runProject({ projectId, runtime, entrypoint, files }) {
  if (!EXECUTOR_URL) {
    throw new Error('VITE_CODE_EXECUTOR_URL not set in .env.local');
  }
  const sessionToken = getSessionToken();
  const startedAt = performance.now();

  let stdout = '';
  let stderr = '';
  let exitCode = 1;
  let status = 'failed';

  try {
    const res = await fetch(`${EXECUTOR_URL}/run_project`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        project_id: projectId,
        entrypoint,
        runtime,
        session_token: sessionToken,
        files: files.map((f) => ({ path: f.path, content_text: f.content_text ?? '' })),
      }),
    });

    if (res.status === 401) {
      const j = await res.json().catch(() => ({}));
      stderr = 'Session expired. Sign in again at app.english-coding.co.uk and reload.';
      status = 'failed';
    } else if (!res.ok) {
      stderr = `Runner HTTP ${res.status}`;
      status = 'infra_error';
    } else {
      const j = await res.json();
      const d = j?.data ?? j;
      stdout = d.stdout ?? d.output ?? '';
      stderr = d.stderr ?? d.error ?? '';
      exitCode = typeof d.exitCode === 'number' ? d.exitCode : (typeof d.exit_code === 'number' ? d.exit_code : 1);
      if (typeof d.timeout !== 'undefined' && d.timeout) {
        status = 'timeout';
      } else {
        status = exitCode === 0 ? 'completed' : 'failed';
      }
    }
  } catch (e) {
    stderr = `Runner error: ${e.message}`;
    status = 'infra_error';
  }

  const duration = Math.round(performance.now() - startedAt);

  // Fire-and-forget log; don't block UI on the audit row
  supabase
    .rpc('ide_record_run', {
      p_session_token: sessionToken,
      p_project_id: projectId,
      p_runtime: runtime,
      p_entrypoint: entrypoint,
      p_status: status,
      p_exit_code: exitCode,
      p_stdout_text: stdout,
      p_stderr_text: stderr,
      p_duration_ms: duration,
    })
    .then(({ error }) => {
      if (error) console.warn('[runner] failed to record run:', error.message);
    });

  return { stdout, stderr, exitCode, status, duration };
}
