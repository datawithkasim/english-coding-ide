-- ============================================================================
-- IDE Phase 3 — Migration 13: ide_record_run + ide_list_runs RPCs
-- ============================================================================
-- The runner flow (client side):
--   1. Client posts files + entrypoint to droplet /run_project
--   2. Droplet returns stdout/stderr/exit_code synchronously
--   3. Client calls ide_record_run to log the result
--   4. Optional: ide_list_runs to render recent run history
--
-- Streaming (WSS) is a Phase 3.5 polish — adds connection state without
-- changing the schema, so the same ide.runs row works either way.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ide_record_run(
  p_session_token text,
  p_project_id    uuid,
  p_runtime       text,
  p_entrypoint    text,
  p_status        text,
  p_exit_code     integer,
  p_stdout_text   text,
  p_stderr_text   text,
  p_duration_ms   integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id   text;
  v_owner_id  text;
  v_is_staff  boolean;
  v_run_id    uuid;
  v_stdout    text;
  v_stderr    text;
BEGIN
  IF NOT ide.has_access(p_session_token) THEN
    RAISE EXCEPTION 'ide_access_denied';
  END IF;

  IF p_status NOT IN ('queued','running','completed','failed','timeout','killed','infra_error') THEN
    RAISE EXCEPTION 'ide_invalid_status';
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

  -- 64 KiB truncation cap per output stream
  v_stdout := CASE WHEN length(p_stdout_text) > 65536
                   THEN substr(p_stdout_text, 1, 65536) || E'\n[... truncated]'
                   ELSE p_stdout_text END;
  v_stderr := CASE WHEN length(p_stderr_text) > 65536
                   THEN substr(p_stderr_text, 1, 65536) || E'\n[... truncated]'
                   ELSE p_stderr_text END;

  INSERT INTO ide.runs (
    project_id, invoker_id, runtime, entrypoint, status,
    exit_code, stdout_text, stderr_text, duration_ms, ended_at
  )
  VALUES (
    p_project_id, v_user_id, p_runtime, p_entrypoint, p_status,
    p_exit_code, v_stdout, v_stderr, p_duration_ms,
    CASE WHEN p_status IN ('completed','failed','timeout','killed','infra_error') THEN now() ELSE NULL END
  )
  RETURNING id INTO v_run_id;

  RETURN v_run_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ide_list_runs(
  p_session_token text,
  p_project_id    uuid,
  p_limit         integer DEFAULT 10
)
RETURNS TABLE (
  id           uuid,
  status       text,
  exit_code    integer,
  duration_ms  integer,
  started_at   timestamptz,
  ended_at     timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id  text;
  v_owner_id text;
  v_is_staff boolean;
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

  RETURN QUERY
    SELECT r.id, r.status, r.exit_code, r.duration_ms, r.started_at, r.ended_at
      FROM ide.runs r
     WHERE r.project_id = p_project_id
     ORDER BY r.started_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 50));
END;
$$;

GRANT EXECUTE ON FUNCTION public.ide_record_run(text, uuid, text, text, text, integer, text, text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ide_list_runs(text, uuid, integer) TO anon, authenticated;

SELECT 'IDE migration 13 (runs RPCs) applied' AS status;
