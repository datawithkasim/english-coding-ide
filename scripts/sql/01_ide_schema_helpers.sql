-- ============================================================================
-- IDE Phase 0 — Migration 01: schema + auth helpers
-- ============================================================================
-- Creates the `ide` schema and three helpers used by every other ide.* RPC.
--
-- Design notes:
--   * Auth piggybacks on the existing app.english-coding session model
--     (app_users.session_token + verify_token_only). No new auth surface.
--   * ide.has_access() = "is this session_token allowed in the IDE at all?"
--     Staff: always allowed. Students: only if feature_flags.ide_enabled=true.
--   * ide.is_staff() = "can this session_token act as teacher in the IDE?"
--     Currently mirrors app_users.role = 'admin' OR an explicit ide.staff row.
--     The staff table is added in migration 02 — this helper short-circuits
--     to admin-role until staff table exists, so 01 is independently runnable.
--   * ide.user_id_from_session() = resolves session to uuid for owner_id fks.
--
-- All helpers are SECURITY DEFINER. RAISE on missing session is intentional —
-- PostgREST surfaces it as HTTP 400 and the client clears the stale token.
--
-- Rollback: DROP SCHEMA ide CASCADE wipes everything ide.* in one shot.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS ide;

-- ---------------------------------------------------------------------------
-- ide.user_id_from_session(p_session_token)
-- Returns the app_users.id for a valid, non-expired session, else NULL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ide.user_id_from_session(p_session_token text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT id
    FROM public.app_users
   WHERE session_token::text = p_session_token
     AND session_expires_at > now()
   LIMIT 1
$$;

-- ---------------------------------------------------------------------------
-- ide.is_staff(p_session_token)
-- True if caller is an admin/teacher. Pre-staff-table: falls back to role.
-- After migration 02 lands, augments with explicit ide.staff membership.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ide.is_staff(p_session_token text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id text;
  v_role    text;
BEGIN
  SELECT id, role
    INTO v_user_id, v_role
    FROM public.app_users
   WHERE session_token::text = p_session_token
     AND session_expires_at > now();

  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_role IN ('admin', 'teacher') THEN
    RETURN true;
  END IF;

  -- Migration 02 adds ide.staff. Check it if the table exists.
  IF to_regclass('ide.staff') IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1 FROM ide.staff WHERE user_id = v_user_id
    );
  END IF;

  RETURN false;
END;
$$;

-- ---------------------------------------------------------------------------
-- ide.has_access(p_session_token)
-- True if caller can use the IDE. Staff always. Students iff feature_flags
-- contains ide_enabled=true (mirrors pygame_enabled rollout pattern).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ide.has_access(p_session_token text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id text;
  v_flags   jsonb;
BEGIN
  SELECT id, feature_flags
    INTO v_user_id, v_flags
    FROM public.app_users
   WHERE session_token::text = p_session_token
     AND session_expires_at > now();

  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF ide.is_staff(p_session_token) THEN
    RETURN true;
  END IF;

  RETURN COALESCE((v_flags ->> 'ide_enabled')::boolean, false);
END;
$$;

REVOKE EXECUTE ON FUNCTION ide.user_id_from_session(text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION ide.is_staff(text)             FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION ide.has_access(text)           FROM anon, authenticated;

SELECT 'IDE migration 01 (schema + helpers) applied' AS status;
