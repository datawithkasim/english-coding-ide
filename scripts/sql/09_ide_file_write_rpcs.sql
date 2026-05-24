-- ============================================================================
-- IDE Phase 1 — Migration 09: file WRITE RPCs (save + autosave)
-- ============================================================================
-- Optimistic concurrency: caller passes p_expected_version; if it doesn't
-- match the current version we raise ide_version_conflict and the client
-- re-fetches. Writes always bump version + log to ide.file_events.
--
-- p_kind distinguishes autosave (debounced editor) from manual_save (Ctrl+S)
-- vs teacher_save (someone with staff role saved a student's file).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ide_save_file(
  p_session_token    text,
  p_file_id          uuid,
  p_content_text     text,
  p_expected_version integer,
  p_kind             text DEFAULT 'auto_save'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id     text;
  v_is_staff    boolean;
  v_project_id  uuid;
  v_owner_id    text;
  v_current_v   integer;
  v_path        text;
  v_size        integer;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  IF p_kind NOT IN ('auto_save','manual_save','teacher_save') THEN
    RAISE EXCEPTION 'ide_invalid_kind';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT f.project_id, p.owner_id, f.version, f.path
    INTO v_project_id, v_owner_id, v_current_v, v_path
    FROM ide.files f
    JOIN ide.projects p ON p.id = f.project_id
   WHERE f.id = p_file_id;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'ide_file_not_found';
  END IF;

  IF v_owner_id <> v_user_id AND NOT v_is_staff THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  IF v_current_v <> p_expected_version THEN
    RAISE EXCEPTION 'ide_version_conflict' USING HINT = format('current=%s expected=%s', v_current_v, p_expected_version);
  END IF;

  v_size := COALESCE(octet_length(p_content_text), 0);
  IF v_size > 1048576 THEN
    RAISE EXCEPTION 'ide_file_too_large';
  END IF;

  UPDATE ide.files
     SET content_text   = p_content_text,
         size_bytes     = v_size,
         version        = version + 1,
         updated_at     = now(),
         last_editor_id = v_user_id
   WHERE id = p_file_id;

  UPDATE ide.projects
     SET updated_at = now()
   WHERE id = v_project_id;

  INSERT INTO ide.file_events (project_id, file_path, kind, actor_id, actor_is_staff, size_bytes)
  VALUES (v_project_id, v_path,
          CASE WHEN v_is_staff AND v_owner_id <> v_user_id THEN 'teacher_save' ELSE p_kind END,
          v_user_id, v_is_staff, v_size);

  RETURN jsonb_build_object('id', p_file_id, 'version', v_current_v + 1, 'size_bytes', v_size);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ide_save_file(text, uuid, text, integer, text) TO anon, authenticated;

SELECT 'IDE migration 09 (file write RPCs) applied' AS status;
