-- ============================================================================
-- IDE Phase 1 — Migration 07: ide_has_access RPC
-- ============================================================================
-- Public RPC wrapping ide.has_access() so PostgREST can call it.
-- App calls this on boot to decide login vs dashboard.
--
-- All public ide_* RPCs follow the same shape:
--   ide_<verb>(p_session_token text, ...) RETURNS <thing>
-- session_token is always first arg.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ide_has_access(p_session_token text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT ide.has_access(p_session_token);
$$;

GRANT EXECUTE ON FUNCTION public.ide_has_access(text) TO anon, authenticated;

SELECT 'IDE migration 07 (ide_has_access RPC) applied' AS status;
