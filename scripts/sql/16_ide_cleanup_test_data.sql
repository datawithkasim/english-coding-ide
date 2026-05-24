-- ============================================================================
-- IDE Phase 3 hardening — Migration 16: cleanup dev test data
-- ============================================================================
-- During Phase 1 testing on 2026-05-24 we created a project in prod under
-- test_26586 to verify the CRUD round-trip. Removing now so prod data
-- is clean before Lab subdomain launch.
--
-- Related concern (no SQL fix possible — see Stage 2 of the hardening plan):
-- the droplet's run_workspace() rejects path strings containing `..` but
-- doesn't reject SYMLINKS created by student code at runtime. The fix lives
-- in extensions/code-executor-multi-file/run_project.py: an os.path.islink()
-- check before each open(full, "w"). This SQL note exists so a future reader
-- of the migration log understands the layered defence.
-- ============================================================================

DELETE FROM ide.file_events
 WHERE project_id = '7370d541-fe9e-42b2-8cf5-aec8887cddc7';

DELETE FROM ide.files
 WHERE project_id = '7370d541-fe9e-42b2-8cf5-aec8887cddc7';

DELETE FROM ide.projects
 WHERE id = '7370d541-fe9e-42b2-8cf5-aec8887cddc7';

SELECT 'IDE migration 16 (cleanup test data) applied' AS status;
