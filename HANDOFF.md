# Lab handoff — what's done, what's left, what only Kasim can do

Built 2026-05-24 across one session, hardened in a follow-up pass that
same day. Phases 1+2 fully shipped (DB + RPCs + client + verified
end-to-end). Phase 3 client+RPCs done; droplet deploy needs your SSH.
Phase 4 infra picks decided + table pre-created. Phases 5-6 parked.

## Risk register

Audit ran across all moving parts. Items below are the live state — what
was found, what was done about it, what you still need to know.

| # | Risk | Status | Notes |
|---|------|--------|-------|
| 1 | `ide.projects.owner_id` + `ide.staff.user_id` ON DELETE CASCADE silently wipes student data if `app_users` row deleted | ✅ Fixed | Migration 14 — both now RESTRICT. Deleting an `app_users` row now raises until you archive their IDE projects first. |
| 2 | `?session=<token>` URL bounce leaks session_token into history / Cloudflare logs / Referer headers | ✅ Fixed | `base44Client.js` sets `ec_session` cookie on `.english-coding.co.uk`; Lab's `bootstrapSession()` reads it first. URL fallback retained for `localhost` dev only. |
| 3 | Symlink injection via student code can leak host files past firejail `--whitelist` | ✅ Fixed | `run_project.py` rejects writes through symlinks with `os.path.lexists() + os.path.islink()` before each `open()`. |
| 4 | `/run_project` stub hardcoded `timeout=15` vs `/execute` `TIMEOUT_SECONDS=10` — regression on single-worker droplet | ✅ Fixed | Stub now defaults to `TIMEOUT_SECONDS` shared with `/execute`. Same starvation envelope as existing route. |
| 5 | Test project from dev session sat in prod | ✅ Cleaned | Migration 16 deleted `7370d541-...` + its files + audit rows. |
| 6 | `ide.file_events` audit log grows unbounded | ✅ Mitigated | Migration 15: `ide.purge_old_file_events(90)` + pg_cron schedule (enable extension in Supabase dashboard to activate; fn callable manually otherwise). |
| 7 | SECURITY DEFINER owner = `postgres` — bypasses RLS on everything | ✅ Documented as intentional | Same pattern as `app.english-coding`'s RPC layer. RLS is defence-in-depth; real protection is in-function `ide.has_access()` + per-resource owner/staff match. Owner change would break read of RLS-protected `app_users`. See header in `scripts/sql/17_ide_doc_snapshots.sql`. |
| 8 | No `lab.english-coding.co.uk` in droplet `ALLOWED_ORIGINS` — students get CORS errors on Run once Lab ships | ⏳ Awaiting your droplet edit | Bundled into the deploy runbook below. |
| 9 | Single uvicorn worker on droplet — one long student loop blocks every other student | ⚠️ Pre-existing, out of scope | Affects both `/execute` and the new `/run_project` equally. Document, fix later by editing systemd `ExecStart` with `--workers 4`. |
| 10 | `firejail` upstream unmaintained since 2023 | ⚠️ Acceptable for now | Low real-world exploit pressure (students aren't pentesters). Plan to migrate to `bubblewrap` or `crun` if cohort > 100. |

## ✅ Live in prod now

**17 SQL migrations applied to Supabase project `zlxrweefpxssbqldewcm`:**

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
| 14 | `projects.owner_id` + `staff.user_id` FKs → RESTRICT (hardening pass) |
| 15 | `ide.purge_old_file_events(days)` + pg_cron schedule (hardening pass) |
| 16 | cleanup dev test project `7370d541-...` (hardening pass) |
| 17 | `ide.doc_snapshots` (Y.js persistence pre-created for Phase 4 — hardening pass) |

All FK columns are `text` (matches `app_users.id` actual type).

**React client** at `src/`:
- `App.jsx` — bootstraps session via cookie or `?session=`, calls `ide_has_access`
- `pages/Dashboard.jsx` — lists + creates projects
- `pages/ProjectView.jsx` — file tree, autosave editor, ▶ Run, archive
- `lib/supabase.js` — cookie-first session bootstrap
- `lib/runner.js` — `runProject()` POSTs `/run_project`, records `ide.runs`
- `components/Editor.jsx` — CodeMirror 6 (Python/JS)
- `components/OutputPanel.jsx` — stdout/stderr/exit + duration

**Cross-app cookie wiring** in `app.english-coding/src/api/base44Client.js`:
- `storeSessionToken()` writes `ec_session` cookie on `.english-coding.co.uk`
- `logout()` + `handleRpcError()` clear cookie alongside localStorage
- Lab reads cookie via `document.cookie` — no URL token bounce in prod

**Dev access:** `test_26586` (password `Pygame-Smoke-2026!`) has
`ide_enabled=true`. Local: `npm run dev` → `http://localhost:5180/?session=<token>`
(localhost can't share cookies with app.english-coding.co.uk, so the URL
fallback stays useful for vite dev).

## ⏳ Needs you — droplet deploy (Phase 3 finish)

Backup BEFORE every scp. The `code-executor` service serves the production
student app — if a syntax error in `main.py` takes the service down,
every student loses the ability to run code in their lessons until you roll
back.

### Step 1 — backup current state (timestamped triple-backup)

```bash
ssh root@167.172.82.155 '
  STAMP=$(date +%Y%m%d-%H%M%S)
  cp /opt/code-executor/main.py /opt/code-executor/main.py.bak-$STAMP
  cp /etc/code-executor.env /opt/code-executor/env.bak-$STAMP
  /opt/code-executor/venv/bin/pip freeze > /opt/code-executor/requirements.bak-$STAMP.txt
  echo "backed up $STAMP"
  ls -lh /opt/code-executor/*.bak-$STAMP* /opt/code-executor/requirements.bak-$STAMP.txt
'
```

### Step 2 — merge the stub into a local copy of main.py

Open `~/Desktop/dev/app.english-coding/code-executor/main.py` and paste from
`~/Desktop/dev/english-coding-ide/extensions/code-executor-multi-file/run_project.py`:

1. Uncomment the `WorkspaceFile` + `RunProjectRequest` Pydantic models,
   paste near `ExecuteRequest` (around line 76).
2. Uncomment the `_safe_workspace_path()` + `run_workspace()` helpers,
   paste near `run_code()` (around line 405). **Hardened version uses the
   shared `TIMEOUT_SECONDS` constant and rejects symlinks before each write.**
3. Uncomment the `@app.post("/run_project")` route, paste below `/execute`
   (around line 660).
4. Update `ALLOWED_ORIGINS` (around line 34) to add Lab origins **in the
   same diff** so it deploys atomically:
   ```python
   ALLOWED_ORIGINS = [
       "https://app.english-coding.co.uk",
       "https://english-coding.co.uk",
       "https://lab.english-coding.co.uk",   # ← new
       "http://localhost:5173",
       "http://localhost:4173",
       "http://localhost:5180",              # ← new (Lab vite default)
   ]
   ```

Local syntax check before scp:
```bash
python3 -m py_compile ~/Desktop/dev/app.english-coding/code-executor/main.py
```

### Step 3 — deploy + restart + health check

```bash
scp ~/Desktop/dev/app.english-coding/code-executor/main.py \
    root@167.172.82.155:/opt/code-executor/main.py

ssh root@167.172.82.155 '
  /opt/code-executor/venv/bin/python -m py_compile /opt/code-executor/main.py || exit 1
  systemctl restart code-executor
  sleep 2
  curl -sf http://localhost:8000/health || exit 1
  echo "health OK"
'
```

### Step 4 — smoke test from your laptop

Get a valid session_token (from any logged-in app.english-coding browser tab,
DevTools → Application → Local Storage → `appUserSession` → `session_token`).

```bash
TOKEN=<paste-here>
# Existing route still works:
curl -X POST https://<droplet-host>/execute \
  -H "Content-Type: application/json" \
  -d "{\"code\":\"print(1)\",\"session_token\":\"$TOKEN\",\"mode\":\"run\"}"
# Expected: {"data":{"stdout":"1\n",...}}

# New route works:
curl -X POST https://<droplet-host>/run_project \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"smoke\",\"entrypoint\":\"main.py\",\"runtime\":\"python\",
       \"session_token\":\"$TOKEN\",\"files\":[{\"path\":\"main.py\",\"content_text\":\"print(2+2)\"}]}"
# Expected: {"data":{"stdout":"4\n","exitCode":0,...}}
```

### Step 5 — rollback (only if step 3 or 4 fails)

```bash
ssh root@167.172.82.155 '
  LATEST=$(ls -t /opt/code-executor/main.py.bak-* | head -1)
  cp $LATEST /opt/code-executor/main.py
  systemctl restart code-executor
  sleep 2
  curl -sf http://localhost:8000/health && echo "rolled back to $LATEST"
'
```

### Step 6 — point Lab at the droplet

Edit `english-coding-ide/.env.local`:
```
VITE_CODE_EXECUTOR_URL=https://<droplet-host>
```

## ⏳ Needs you — deploy Lab subdomain

`lab.english-coding.co.uk` doesn't exist yet. To ship:

1. Push this repo to GitHub (`datawithkasim/english-coding-ide`)
2. DigitalOcean App Platform → Create App → from repo (autodeploy on main)
3. Env vars on DO: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`,
   `VITE_APP_URL`, `VITE_CODE_EXECUTOR_URL` (same as `.env.local`)
4. Cloudflare DNS: CNAME `lab` → `<do-app>.ondigitalocean.app`
5. Push the `app.english-coding` cookie-widen change (auto-deploys) so the
   cookie gets set on student logins.
6. Verify: log into `app.english-coding.co.uk` as test_26586 → open
   `https://lab.english-coding.co.uk` in same browser → dashboard loads
   without any URL token. DevTools → Application → Cookies →
   `english-coding.co.uk` → `ec_session` present.

## 📦 Phase 4 prep — Hocuspocus collab (decisions baked, no code yet)

- **Persistence**: Migration 17 already created `ide.doc_snapshots(file_id PK, project_id, ydoc bytea, version, updated_at)`. The `@hocuspocus/extension-database` Postgres adapter writes here.
- **Host**: **New DO Droplet, sibling to `python-ide-sgp1`.** 2 vCPU / 2 GB, Ubuntu 24.04, sgp1 region (~$12-$24/mo). Same ops surface you already use for code-executor.
- **Auth**: `onAuthenticate` hook calls `ide_has_access(p_session_token)` over PostgREST. Y.js doc id = `ide.files.id`.
- **Service shape** (write `hocuspocus-droplet-spec.md` later):
  - Node 20 LTS via nvm
  - systemd unit at `/etc/systemd/system/hocuspocus.service`
  - reads `SUPABASE_URL` + `SUPABASE_SECRET_KEY` from `/etc/hocuspocus.env`
  - Caddy in front for TLS termination on port 443

Estimate ~half-day to ship Phase 4 end-to-end once you decide to start.

## 📦 Phase 3b prep — Pygame = REUSE, not new infra

`app.english-coding/src/workers/pygame.worker.js` already loads Pyodide +
pygame-ce from jsDelivr CDN in a Web Worker. `src/components/ide/PyGameRunner.jsx`
is the consuming component. The worker has no `window` access — student code
cannot extract the session token.

Plan: copy both files into `english-coding-ide/src/` (paths preserved),
add `pygame` to the `ide.projects.runtime` CHECK constraint via a Phase 3b
migration, render `PyGameRunner` instead of the regular `OutputPanel` when
`project.runtime === 'pygame'`. **Cancel pygbag plan** — it would be more
infra for no benefit. Reuses existing battle-tested code.

## 📦 Other parked phases

| Phase | Why blocked |
|-------|-------------|
| 5 | Teacher dashboard — depends on Phase 3 live in production |
| 6 | Korean sweep + iPad QA + cohort onboard — last (don't translate before flows are final) |

## How to verify Phases 1+2 right now (no droplet needed)

```bash
cd Desktop/dev/english-coding-ide
npm install  # one-time
npm run dev  # localhost:5180
```

Get a session_token by logging in to app.english-coding.co.uk as `test_26586`.
DevTools → Application → Local Storage → `appUserSession` → copy `session_token`.

Open `http://localhost:5180/?session=<that-token>`.

Create a project, edit, save (autosave shows "Saved"), rename a file,
delete, create new file, archive project. All round-trip to prod Supabase.

## Rollback

**Lab/IDE schema (full nuke):**
```sql
DROP SCHEMA ide CASCADE;
```
Wipes every IDE table + RPC in one shot. Touches zero `public.*` data.

**Single hardening migration (if 14-17 needs revert):**
- 14: re-DROP + re-ADD constraints with `ON DELETE CASCADE`
- 15: `SELECT cron.unschedule('ide-purge-file-events'); DROP FUNCTION ide.purge_old_file_events(integer);`
- 16: not reversible (test data is gone, but you don't want it back anyway)
- 17: `DROP TABLE ide.doc_snapshots;`

**Droplet:** see step 5 above. Each scp leaves a timestamped backup.

**Cookie-widen:** revert the app.english-coding commit (`base44Client.js`) +
push. localStorage path still works on its own.
