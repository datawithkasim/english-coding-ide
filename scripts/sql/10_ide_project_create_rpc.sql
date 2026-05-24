-- ============================================================================
-- IDE Phase 1 — Migration 10: ide_create_project RPC + starter file
-- ============================================================================
-- Atomically create a project + its entrypoint file. Slug derived from name.
-- Returns the new project id so the client can navigate straight in.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ide_create_project(
  p_session_token text,
  p_name          text,
  p_runtime       text DEFAULT 'python'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id   text;
  v_slug      text;
  v_project_id uuid;
  v_entry     text;
  v_starter   text;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  IF p_runtime NOT IN ('python','javascript') THEN
    RAISE EXCEPTION 'ide_invalid_runtime';
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RAISE EXCEPTION 'ide_invalid_name';
  END IF;

  v_user_id := ide.user_id_from_session(p_session_token);

  v_slug := regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g');
  v_slug := regexp_replace(v_slug, '(^-+|-+$)', '', 'g');
  IF length(v_slug) = 0 THEN
    v_slug := 'project';
  END IF;
  -- ensure uniqueness per owner
  WHILE EXISTS (SELECT 1 FROM ide.projects WHERE owner_id = v_user_id AND slug = v_slug) LOOP
    v_slug := v_slug || '-' || substr(md5(random()::text), 1, 4);
  END LOOP;

  v_entry := CASE p_runtime WHEN 'javascript' THEN 'main.js' ELSE 'main.py' END;
  v_starter := CASE p_runtime
                 WHEN 'javascript' THEN E'// 새 프로젝트입니다. 첫 줄을 작성해 보세요.\nconsole.log("hello, world");\n'
                 ELSE                   E'# 새 프로젝트입니다. 첫 줄을 작성해 보세요.\nprint("hello, world")\n'
               END;

  INSERT INTO ide.projects (owner_id, name, slug, runtime, entrypoint)
  VALUES (v_user_id, trim(p_name), v_slug, p_runtime, v_entry)
  RETURNING id INTO v_project_id;

  INSERT INTO ide.files (project_id, path, content_text, size_bytes, last_editor_id)
  VALUES (v_project_id, v_entry, v_starter, octet_length(v_starter), v_user_id);

  INSERT INTO ide.file_events (project_id, file_path, kind, actor_id, actor_is_staff, size_bytes)
  VALUES (v_project_id, v_entry, 'created', v_user_id, ide.is_staff(p_session_token), octet_length(v_starter));

  RETURN v_project_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ide_create_project(text, text, text) TO anon, authenticated;

SELECT 'IDE migration 10 (ide_create_project RPC) applied' AS status;
