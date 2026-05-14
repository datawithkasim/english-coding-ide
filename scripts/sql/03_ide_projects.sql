-- ============================================================================
-- IDE Phase 0 — Migration 03: ide.projects
-- ============================================================================
-- One row per student workspace. A student can have many projects (e.g.
-- "week-3-loops", "free-play", "capstone"). Each project owns N files.
--
-- entrypoint is the path of the file to exec on Run (default "main.py").
-- runtime is "python" | "javascript" — drives node-vs-python3 in executor.
-- archived_at keeps rows for audit but hides from default project list.
--
-- All reads/writes via SECURITY DEFINER RPCs — no direct PostgREST access.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ide.projects (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      uuid NOT NULL REFERENCES public.app_users(id) ON DELETE CASCADE,
  name          text NOT NULL,
  slug          text NOT NULL,
  runtime       text NOT NULL DEFAULT 'python' CHECK (runtime IN ('python', 'javascript')),
  entrypoint    text NOT NULL DEFAULT 'main.py',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  archived_at   timestamptz,
  UNIQUE (owner_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_ide_projects_owner ON ide.projects (owner_id) WHERE archived_at IS NULL;

ALTER TABLE ide.projects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS projects_no_direct_access ON ide.projects;
CREATE POLICY projects_no_direct_access ON ide.projects
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

SELECT 'IDE migration 03 (ide.projects) applied' AS status;
