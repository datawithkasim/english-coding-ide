-- ============================================================================
-- IDE Phase 3 hardening — Migration 15: 90-day retention on ide.file_events
-- ============================================================================
-- file_events is append-only audit. At 1000 saves/student/month × 100
-- students = ~100k rows/mo. No upper bound. Add a nightly purge.
--
-- 90 days = enough window for "teacher edited Y file 2 months ago"
-- forensics + cheat-detection without keeping every keystroke forever.
--
-- pg_cron is a Supabase-managed extension — `CREATE EXTENSION` requires
-- superuser, so this migration only schedules if the extension is already
-- enabled. To enable: Supabase dashboard → Database → Extensions → pg_cron.
-- Without pg_cron, the purge fn exists and can be invoked manually.
-- ============================================================================

CREATE OR REPLACE FUNCTION ide.purge_old_file_events(p_days integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ide, pg_temp
AS $$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM ide.file_events
   WHERE occurred_at < now() - (p_days || ' days')::interval;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE EXECUTE ON FUNCTION ide.purge_old_file_events(integer) FROM anon, authenticated;

-- Schedule nightly only if pg_cron is enabled. Idempotent: cron.schedule
-- with a duplicate jobname raises; wrap with a guard.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('ide-purge-file-events')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ide-purge-file-events');
    PERFORM cron.schedule(
      'ide-purge-file-events',
      '0 4 * * *',
      $cron$SELECT ide.purge_old_file_events(90)$cron$
    );
  ELSE
    RAISE NOTICE 'pg_cron not enabled — purge fn created but not scheduled. Enable in Supabase dashboard then re-run this migration.';
  END IF;
END $$;

SELECT 'IDE migration 15 (file_events 90-day retention) applied' AS status;
