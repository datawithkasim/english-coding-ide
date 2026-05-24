-- ============================================================================
-- IDE Phase 2 — Migration 12: ide_archive_project RPC
-- ============================================================================
-- Soft-delete via archived_at. Hidden from ide_list_projects, audit preserved.
-- Unarchive flips the column back to NULL.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ide_archive_project(
  p_session_token text,
  p_project_id    uuid,
  p_archive       boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id  text;
  v_is_staff boolean;
  v_owner_id text;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT owner_id INTO v_owner_id FROM ide.projects WHERE id = p_project_id;
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'ide_project_not_found';
  END IF;
  IF v_owner_id <> v_user_id AND NOT v_is_staff THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  UPDATE ide.projects
     SET archived_at = CASE WHEN p_archive THEN now() ELSE NULL END,
         updated_at  = now()
   WHERE id = p_project_id;

  RETURN jsonb_build_object('id', p_project_id, 'archived', p_archive);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ide_archive_project(text, uuid, boolean) TO anon, authenticated;

SELECT 'IDE migration 12 (ide_archive_project RPC) applied' AS status;
