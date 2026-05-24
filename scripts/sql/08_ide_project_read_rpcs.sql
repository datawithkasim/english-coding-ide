-- ============================================================================
-- IDE Phase 1 — Migration 08: project + file READ RPCs
-- ============================================================================
-- Read-side endpoints for the dashboard + editor. All gated by ide.has_access.
--
-- Access rules:
--   * Students see only their own projects + files.
--   * Staff see everyone's projects (for the future teacher dashboard).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ide_list_projects — caller's project list (most recent first, non-archived)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ide_list_projects(p_session_token text)
RETURNS TABLE (
  id          uuid,
  name        text,
  slug        text,
  runtime     text,
  entrypoint  text,
  updated_at  timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id text;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);

  RETURN QUERY
    SELECT p.id, p.name, p.slug, p.runtime, p.entrypoint, p.updated_at
      FROM ide.projects p
     WHERE p.owner_id = v_user_id
       AND p.archived_at IS NULL
     ORDER BY p.updated_at DESC;
END;
$$;

-- ---------------------------------------------------------------------------
-- ide_get_project — project metadata + file index (paths + sizes only).
-- File content fetched separately via ide_get_file.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ide_get_project(p_session_token text, p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id text;
  v_is_staff boolean;
  v_project jsonb;
  v_files jsonb;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT to_jsonb(p) INTO v_project
    FROM ide.projects p
   WHERE p.id = p_project_id
     AND (p.owner_id = v_user_id OR v_is_staff);

  IF v_project IS NULL THEN
    RAISE EXCEPTION 'ide_project_not_found';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', f.id,
            'path', f.path,
            'size_bytes', f.size_bytes,
            'version', f.version,
            'updated_at', f.updated_at
         ) ORDER BY f.path), '[]'::jsonb)
    INTO v_files
    FROM ide.files f
   WHERE f.project_id = p_project_id;

  RETURN jsonb_build_object('project', v_project, 'files', v_files);
END;
$$;

-- ---------------------------------------------------------------------------
-- ide_get_file — single file content + version (for optimistic-concurrency
-- save). Caller must own the project OR be staff.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ide_get_file(p_session_token text, p_file_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id text;
  v_is_staff boolean;
  v_file jsonb;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT to_jsonb(f) INTO v_file
    FROM ide.files f
    JOIN ide.projects p ON p.id = f.project_id
   WHERE f.id = p_file_id
     AND (p.owner_id = v_user_id OR v_is_staff);

  IF v_file IS NULL THEN
    RAISE EXCEPTION 'ide_file_not_found';
  END IF;

  RETURN v_file;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ide_list_projects(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ide_get_project(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ide_get_file(text, uuid) TO anon, authenticated;

SELECT 'IDE migration 08 (project read RPCs) applied' AS status;
