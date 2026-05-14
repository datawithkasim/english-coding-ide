-- ============================================================================
-- IDE Phase 0 — Migration 06: ide.file_events
-- ============================================================================
-- Append-only audit log of file mutations. Used for:
--   * "Teacher edited main.py 3 min ago" timeline on student dashboard
--   * Forensics — who changed what when, anti-cheat trail
--   * Phase 4 collab — feeds Y.js doc reconstruction if Hocuspocus state lost
--
-- We do NOT store full diffs (too costly) — only event kind + size + actor.
-- For diff-style audit later, layer a "snapshots" table on top.
--
-- kind:
--   'created' / 'updated' / 'deleted' / 'renamed' (from_path stored)
--   'auto_save' (debounced autosave) / 'manual_save' / 'teacher_save'
-- ============================================================================

CREATE TABLE IF NOT EXISTS ide.file_events (
  id            bigserial PRIMARY KEY,
  project_id    uuid NOT NULL REFERENCES ide.projects(id) ON DELETE CASCADE,
  file_path     text NOT NULL,
  from_path     text,
  kind          text NOT NULL
                  CHECK (kind IN ('created','updated','deleted','renamed','auto_save','manual_save','teacher_save')),
  actor_id      uuid NOT NULL REFERENCES public.app_users(id),
  actor_is_staff boolean NOT NULL DEFAULT false,
  size_bytes    integer,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ide_file_events_project_time ON ide.file_events (project_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ide_file_events_actor       ON ide.file_events (actor_id);

ALTER TABLE ide.file_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS file_events_no_direct_access ON ide.file_events;
CREATE POLICY file_events_no_direct_access ON ide.file_events
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

SELECT 'IDE migration 06 (ide.file_events) applied' AS status;
