-- ============================================================================
-- IDE Phase 2 — Migration 11: file CRUD RPCs (create / rename / delete)
-- ============================================================================
-- Path rules (validated in ide.validate_path):
--   * POSIX relative path: "main.py", "lib/utils.py", "assets/sprite.png"
--   * No leading slash, no ".." segments, no empty segments, no NUL bytes
--   * Max 255 chars total; per-segment max 100 chars
--   * Allowed chars: alnum + . _ -
--
-- Each mutation logs to ide.file_events for the audit log.
-- ============================================================================

CREATE OR REPLACE FUNCTION ide.validate_path(p_path text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_seg text;
BEGIN
  IF p_path IS NULL OR length(p_path) = 0 OR length(p_path) > 255 THEN
    RAISE EXCEPTION 'ide_invalid_path' USING HINT = 'empty or too long';
  END IF;
  IF p_path LIKE '/%' THEN
    RAISE EXCEPTION 'ide_invalid_path' USING HINT = 'absolute path not allowed';
  END IF;
  -- NUL bytes are rejected by the text type itself before reaching here.
  FOREACH v_seg IN ARRAY string_to_array(p_path, '/') LOOP
    IF v_seg = '' OR v_seg = '..' OR v_seg = '.' THEN
      RAISE EXCEPTION 'ide_invalid_path' USING HINT = 'empty or traversal segment';
    END IF;
    IF length(v_seg) > 100 THEN
      RAISE EXCEPTION 'ide_invalid_path' USING HINT = 'segment too long';
    END IF;
    IF v_seg !~ '^[A-Za-z0-9._-]+$' THEN
      RAISE EXCEPTION 'ide_invalid_path' USING HINT = 'illegal characters';
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- ide_create_file — empty file at p_path. Caller must own the project.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ide_create_file(
  p_session_token text,
  p_project_id    uuid,
  p_path          text,
  p_content_text  text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id   text;
  v_owner_id  text;
  v_is_staff  boolean;
  v_file_id   uuid;
  v_size      integer;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;
  PERFORM ide.validate_path(p_path);

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT owner_id INTO v_owner_id FROM ide.projects WHERE id = p_project_id;
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'ide_project_not_found';
  END IF;
  IF v_owner_id <> v_user_id AND NOT v_is_staff THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  v_size := COALESCE(octet_length(p_content_text), 0);
  IF v_size > 1048576 THEN
    RAISE EXCEPTION 'ide_file_too_large';
  END IF;

  BEGIN
    INSERT INTO ide.files (project_id, path, content_text, size_bytes, last_editor_id)
    VALUES (p_project_id, p_path, p_content_text, v_size, v_user_id)
    RETURNING id INTO v_file_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'ide_path_exists';
  END;

  INSERT INTO ide.file_events (project_id, file_path, kind, actor_id, actor_is_staff, size_bytes)
  VALUES (p_project_id, p_path, 'created', v_user_id, v_is_staff, v_size);

  UPDATE ide.projects SET updated_at = now() WHERE id = p_project_id;

  RETURN jsonb_build_object('id', v_file_id, 'path', p_path, 'version', 1, 'size_bytes', v_size);
END;
$$;

-- ---------------------------------------------------------------------------
-- ide_rename_file — move file to new path.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ide_rename_file(
  p_session_token text,
  p_file_id       uuid,
  p_new_path      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id    text;
  v_is_staff   boolean;
  v_project_id uuid;
  v_owner_id   text;
  v_old_path   text;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;
  PERFORM ide.validate_path(p_new_path);

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT f.project_id, p.owner_id, f.path
    INTO v_project_id, v_owner_id, v_old_path
    FROM ide.files f
    JOIN ide.projects p ON p.id = f.project_id
   WHERE f.id = p_file_id;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'ide_file_not_found';
  END IF;
  IF v_owner_id <> v_user_id AND NOT v_is_staff THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  IF v_old_path = p_new_path THEN
    RETURN jsonb_build_object('id', p_file_id, 'path', p_new_path);
  END IF;

  BEGIN
    UPDATE ide.files SET path = p_new_path, updated_at = now(), last_editor_id = v_user_id
     WHERE id = p_file_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'ide_path_exists';
  END;

  INSERT INTO ide.file_events (project_id, file_path, from_path, kind, actor_id, actor_is_staff)
  VALUES (v_project_id, p_new_path, v_old_path, 'renamed', v_user_id, v_is_staff);

  -- if the renamed file was the project's entrypoint, update it
  UPDATE ide.projects
     SET entrypoint = p_new_path, updated_at = now()
   WHERE id = v_project_id AND entrypoint = v_old_path;

  UPDATE ide.projects SET updated_at = now() WHERE id = v_project_id;

  RETURN jsonb_build_object('id', p_file_id, 'path', p_new_path, 'from_path', v_old_path);
END;
$$;

-- ---------------------------------------------------------------------------
-- ide_delete_file — hard delete + audit row.
-- Blocks deleting the entrypoint file (would orphan the project).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ide_delete_file(
  p_session_token text,
  p_file_id       uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id    text;
  v_is_staff   boolean;
  v_project_id uuid;
  v_owner_id   text;
  v_path       text;
  v_entry      text;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);
  v_is_staff := ide.is_staff(p_session_token);

  SELECT f.project_id, p.owner_id, f.path, p.entrypoint
    INTO v_project_id, v_owner_id, v_path, v_entry
    FROM ide.files f
    JOIN ide.projects p ON p.id = f.project_id
   WHERE f.id = p_file_id;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'ide_file_not_found';
  END IF;
  IF v_owner_id <> v_user_id AND NOT v_is_staff THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;
  IF v_path = v_entry THEN
    RAISE EXCEPTION 'ide_cannot_delete_entrypoint';
  END IF;

  DELETE FROM ide.files WHERE id = p_file_id;

  INSERT INTO ide.file_events (project_id, file_path, kind, actor_id, actor_is_staff)
  VALUES (v_project_id, v_path, 'deleted', v_user_id, v_is_staff);

  UPDATE ide.projects SET updated_at = now() WHERE id = v_project_id;

  RETURN jsonb_build_object('id', p_file_id, 'path', v_path);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ide_create_file(text, uuid, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ide_rename_file(text, uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ide_delete_file(text, uuid) TO anon, authenticated;

SELECT 'IDE migration 11 (file CRUD RPCs) applied' AS status;
