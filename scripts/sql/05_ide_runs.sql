-- ============================================================================
-- IDE Phase 0 — Migration 05: ide.runs
-- ============================================================================
-- One row per Run/Stop invocation. Stores stdout/stderr/exit_code/duration
-- for debugging + teacher review ("show me what they ran 5 min ago").
--
-- stdout_text / stderr_text are capped to 64 KiB each at insert time by the
-- runner edge fn — bigger blobs get truncated with a "[...]" marker.
--
-- status:
--   'queued'      — request received, container not yet spawned
--   'running'     — container running
--   'completed'   — exit_code = 0
--   'failed'      — exit_code != 0 (runtime error, not infra error)
--   'timeout'     — wall-clock exceeded
--   'killed'      — user clicked Stop
--   'infra_error' — sandbox spawn failed (alert-worthy)
-- ============================================================================

CREATE TABLE IF NOT EXISTS ide.runs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id    uuid NOT NULL REFERENCES ide.projects(id) ON DELETE CASCADE,
  invoker_id    text NOT NULL REFERENCES public.app_users(id),
  runtime       text NOT NULL,
  entrypoint    text NOT NULL,
  status        text NOT NULL DEFAULT 'queued'
                  CHECK (status IN ('queued','running','completed','failed','timeout','killed','infra_error')),
  exit_code     integer,
  stdout_text   text,
  stderr_text   text,
  duration_ms   integer,
  started_at    timestamptz NOT NULL DEFAULT now(),
  ended_at      timestamptz
);

CREATE INDEX IF NOT EXISTS idx_ide_runs_project_started ON ide.runs (project_id, started_at DESC);

ALTER TABLE ide.runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS runs_no_direct_access ON ide.runs;
CREATE POLICY runs_no_direct_access ON ide.runs
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

SELECT 'IDE migration 05 (ide.runs) applied' AS status;
