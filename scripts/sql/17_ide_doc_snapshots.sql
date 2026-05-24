-- ============================================================================
-- IDE Phase 4 prep — Migration 17: ide.doc_snapshots (Y.js persistence)
-- ============================================================================
-- Hocuspocus collaboration server (Phase 4) needs somewhere to persist Y.js
-- doc state across reconnects + server restarts. The @hocuspocus/extension-
-- database adapter wants a single table with (name → bytea snapshot).
--
-- We key on file_id (one CRDT doc per file) and store the Y.js update vector
-- as bytea. Version is a monotonic counter the adapter bumps on each write.
--
-- RLS denies all direct access. Reads + writes go through the Hocuspocus
-- service role (added in Phase 4 — `ide.hocuspocus_writer` granted via a
-- follow-up migration) so no anon/authenticated path can leak doc state.
--
-- ---------------------------------------------------------------------------
-- SECURITY MODEL NOTE (applies to all ide.* SECURITY DEFINER fns):
--   All ide.* and public.ide_* SECURITY DEFINER functions are owned by
--   `postgres` (superuser). This bypasses RLS on every table they touch,
--   including public.app_users. Security is enforced by IN-FUNCTION CHECKS:
--   every RPC starts with `IF NOT ide.has_access(p_session_token) THEN
--   RAISE EXCEPTION 'ide_access_denied'` plus per-resource owner / staff
--   match. RLS deny-all policies on ide.* tables are defence-in-depth only.
--   DO NOT change function owners to `authenticator` — that would break the
--   read of public.app_users.session_token in ide.user_id_from_session
--   (which is RLS-protected on app_users). This pattern mirrors how
--   app.english-coding's RPC layer works.
-- ---------------------------------------------------------------------------
-- ============================================================================

CREATE TABLE IF NOT EXISTS ide.doc_snapshots (
  file_id     uuid PRIMARY KEY REFERENCES ide.files(id) ON DELETE CASCADE,
  project_id  uuid NOT NULL REFERENCES ide.projects(id) ON DELETE CASCADE,
  ydoc        bytea NOT NULL,
  version     integer NOT NULL DEFAULT 1,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ide_doc_snapshots_project
  ON ide.doc_snapshots (project_id);

ALTER TABLE ide.doc_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS doc_snapshots_no_direct_access ON ide.doc_snapshots;
CREATE POLICY doc_snapshots_no_direct_access ON ide.doc_snapshots
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

SELECT 'IDE migration 17 (ide.doc_snapshots + security model doc) applied' AS status;
