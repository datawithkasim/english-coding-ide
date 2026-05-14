-- ============================================================================
-- IDE Phase 0 — Migration 04: ide.files
-- ============================================================================
-- Path-based virtual filesystem. Files belong to a project; path is the full
-- POSIX-style relative path ("main.py", "lib/utils.py", "assets/sprite.png").
--
-- content_text holds source files (UTF-8). content_b64 (NULL by default) is
-- reserved for binary assets — added only when image/audio upload is wired
-- (Phase 3b+).
--
-- version is bumped on every write — drives optimistic-concurrency conflict
-- detection in autosave. last_editor_id lets the teacher dashboard show
-- "edited by Kasim 3s ago" vs "edited by student".
--
-- (project_id, path) is unique — no two files at the same path in a project.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ide.files (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id      uuid NOT NULL REFERENCES ide.projects(id) ON DELETE CASCADE,
  path            text NOT NULL,
  content_text    text,
  content_b64     text,
  size_bytes      integer NOT NULL DEFAULT 0,
  version         integer NOT NULL DEFAULT 1,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  last_editor_id  uuid REFERENCES public.app_users(id),
  CHECK (content_text IS NOT NULL OR content_b64 IS NOT NULL),
  CHECK (size_bytes <= 1048576),  -- 1 MiB per file hard cap
  UNIQUE (project_id, path)
);

CREATE INDEX IF NOT EXISTS idx_ide_files_project ON ide.files (project_id);

ALTER TABLE ide.files ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS files_no_direct_access ON ide.files;
CREATE POLICY files_no_direct_access ON ide.files
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

SELECT 'IDE migration 04 (ide.files) applied' AS status;
