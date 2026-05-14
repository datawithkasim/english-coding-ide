-- ============================================================================
-- IDE Phase 0 — Migration 02: ide.staff
-- ============================================================================
-- Explicit staff allowlist beyond app_users.role = 'admin'. Lets us grant
-- IDE-only teacher access without elevating to full admin in app.english-coding.
--
-- Currently empty by design — seed Kasim's account in a follow-up patch once
-- ide.user_id_from_session resolves his uuid in prod.
-- ============================================================================

CREATE TABLE IF NOT EXISTS ide.staff (
  user_id     uuid PRIMARY KEY REFERENCES public.app_users(id) ON DELETE CASCADE,
  granted_at  timestamptz NOT NULL DEFAULT now(),
  granted_by  uuid REFERENCES public.app_users(id),
  notes       text
);

ALTER TABLE ide.staff ENABLE ROW LEVEL SECURITY;

-- Only staff can see the staff list.
DROP POLICY IF EXISTS staff_select_self ON ide.staff;
CREATE POLICY staff_select_self ON ide.staff
  FOR SELECT TO anon, authenticated
  USING (false);  -- All reads via SECURITY DEFINER RPCs only.

DROP POLICY IF EXISTS staff_no_direct_write ON ide.staff;
CREATE POLICY staff_no_direct_write ON ide.staff
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

SELECT 'IDE migration 02 (ide.staff) applied' AS status;
