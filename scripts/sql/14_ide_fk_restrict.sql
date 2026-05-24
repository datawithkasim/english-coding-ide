-- ============================================================================
-- IDE Phase 3 hardening — Migration 14: FKs to app_users → RESTRICT
-- ============================================================================
-- Originally `ide.projects.owner_id` and `ide.staff.user_id` were declared
-- ON DELETE CASCADE in migrations 03 + 02. That means: if an admin script
-- deletes a `public.app_users` row, every IDE project and file the student
-- ever created vanishes with no audit trail.
--
-- Other FK columns referencing public.app_users (`files.last_editor_id`,
-- `runs.invoker_id`, `file_events.actor_id`, `staff.granted_by`) were
-- already created with NO ACTION (Postgres' default), which is functionally
-- equivalent for our purposes — flip the two CASCADE pairs to RESTRICT
-- so deletion is explicitly blocked and the admin must archive first.
--
-- Intra-ide CASCADEs (`files.project_id`, `runs.project_id`,
-- `file_events.project_id` → `ide.projects.id`) STAY — those are the
-- intended behavior when `ide.projects` is hard-deleted.
-- ============================================================================

ALTER TABLE ide.projects
  DROP CONSTRAINT projects_owner_id_fkey,
  ADD CONSTRAINT projects_owner_id_fkey
    FOREIGN KEY (owner_id)
    REFERENCES public.app_users(id)
    ON DELETE RESTRICT;

ALTER TABLE ide.staff
  DROP CONSTRAINT staff_user_id_fkey,
  ADD CONSTRAINT staff_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public.app_users(id)
    ON DELETE RESTRICT;

SELECT 'IDE migration 14 (FKs to app_users → RESTRICT) applied' AS status;
