# Lab handoff — what's done, what's left, what only Kasim can do

Built across one session 2026-05-24. Phases 1+2 fully shipped (DB + RPCs +
client + verified end-to-end). Phase 3 client+RPCs done; droplet deploy
needs your SSH. Phases 4-6 parked.

## ✅ Live in prod now

**13 SQL migrations applied to Supabase project `zlxrweefpxssbqldewcm`:**

| # | What |
|---|------|
| 01 | `ide` schema + `has_access` / `is_staff` / `user_id_from_session` helpers |
| 02 | `ide.staff` table (empty by default, deny-all RLS) |
| 03 | `ide.projects` (one row per student workspace, soft-archive) |
| 04 | `ide.files` (path-based VFS, 1 MiB cap, version counter) |
| 05 | `ide.runs` (stdout/stderr capped at 64 KiB) |
| 06 | `ide.file_events` (append-only audit log) |
| 07 | `ide_has_access(text)` RPC |
| 08 | `ide_list_projects` / `ide_get_project` / `ide_get_file` RPCs |
| 09 | `ide_save_file` RPC (optimistic concurrency, throws `ide_version_conflict`) |
| 10 | `ide_create_project` RPC (atomic project + starter file) |
| 11 | `ide_create_file` / `ide_rename_file` / `ide_delete_file` + path validator |
| 12 | `ide_archive_project` |
| 13 | `ide_record_run` / `ide_list_runs` |

All FK columns are `text` (matches `app_users.id` actual type — original
migration draft used `uuid` and failed at apply time, fixed in commit).

**React client** at `src/`:
- `App.jsx` — bootstraps session via `?session=<token>`, calls `ide_has_access`
- `pages/Dashboard.jsx` — lists + creates projects
- `pages/ProjectView.jsx` — file tree, autosave editor, ▶ Run, archive
- `lib/supabase.js` — session bootstrap (localStorage `ec_session_token`)
- `lib/runner.js` — `runProject()` POSTs `/run_project`, records `ide.runs`
- `components/Editor.jsx` — CodeMirror 6 (Python/JS)
- `components/OutputPanel.jsx` — stdout/stderr/exit + duration

**Dev access:** test_26586 (password `Pygame-Smoke-2026!`) has `ide_enabled=true`.
Local: `npm run dev` → `http://localhost:5180/?session=<token>` (paste any
fresh session_token from `auth_login`).

## ⏳ Needs you — droplet deploy (Phase 3 finish)

The runner code is drafted in `extensions/code-executor-multi-file/run_project.py`
(designed to paste into the existing droplet `main.py`). Steps:

1. **scp the extension** to `/opt/code-executor/main.py` on `167.172.82.155`:
   - Uncomment the `WorkspaceFile` / `RunProjectRequest` models, paste near `ExecuteRequest`
   - Uncomment the `run_workspace()` helper, paste near `run_code()`
   - Uncomment the `/run_project` route, paste below `/execute`
2. `systemctl restart code-executor` on the droplet
3. Smoke test (from local):
   ```bash
   curl -X POST https://<droplet-host>/run_project \
     -H "Content-Type: application/json" \
     -d '{"project_id":"smoke","entrypoint":"main.py","runtime":"python",
          "session_token":"<token>","files":[{"path":"main.py","content_text":"print(1+1)"}]}'
   ```
4. Set the URL in `english-coding-ide/.env.local`:
   ```
   VITE_CODE_EXECUTOR_URL=https://<droplet-host>
   ```

## ⏳ Needs you — deploy Lab itself

`lab.english-coding.co.uk` doesn't exist yet. To ship:

1. Push this repo to GitHub (`datawithkasim/english-coding-ide`)
2. DigitalOcean App Platform → Create App → from repo (autodeploy on main)
3. Env vars on DO: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`,
   `VITE_APP_URL`, `VITE_CODE_EXECUTOR_URL`
4. Cloudflare DNS: CNAME `lab` → `<do-app>.ondigitalocean.app`
5. Add `https://lab.english-coding.co.uk` to droplet `ALLOWED_ORIGINS`
   in `code-executor/main.py` (Phase 2 lockdown CORS list)

## 📦 Parked phases (4-6)

| Phase | What | Why blocked |
|-------|------|-------------|
| 3b | pygbag pipeline for Pygame | Needs Phase 3 droplet live first |
| 4 | Hocuspocus live collab + presence | Needs separate Node server deploy |
| 5 | Teacher dashboard | Depends on Phase 3 in production |
| 6 | Korean sweep + iPad QA + onboard | Last (don't translate before flows are final) |

Estimate: Phase 4 alone ~half-day (Hocuspocus server setup, y-codemirror,
auth glue). Phases 5+6 ~1 day after that.

## How to verify Phase 1+2 right now (no droplet needed)

```bash
cd Desktop/dev/english-coding-ide
npm install  # one-time
npm run dev  # localhost:5180
```

Then in another tab, get a session_token by logging in to
app.english-coding.co.uk as test_26586. Copy from localStorage:
`localStorage.getItem('appUserSession')` → parse → `.session_token`.

Open `http://localhost:5180/?session=<that-token>`.
Create a project, edit, save (autosave shows "Saved"), rename a file,
delete, create new file, archive project. All round-trip to prod Supabase.

## Rollback

```sql
DROP SCHEMA ide CASCADE;
```
Wipes every IDE table + RPC in one shot. Touches zero `public.*` data.
