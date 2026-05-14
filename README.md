# English Coding Lab — internal IDE

Standalone subdomain (`lab.english-coding.co.uk`) where students do classwork.
Replaces Replit for class projects.

## Architecture (Phase 0)

```
┌─────────────────────────────────┐
│ lab.english-coding.co.uk        │  Vite + React + CodeMirror 6
│   (this repo)                   │  Reuses app.english-coding session_token.
└─────────────┬───────────────────┘
              │ session_token cookie / query
              ▼
┌─────────────────────────────────┐
│ Supabase (shared)               │  ide.* schema only — zero touch to public.*
│   ide.projects · ide.files      │  Helpers: ide.has_access(), ide.is_staff()
│   ide.runs    · ide.file_events │
└─────────────┬───────────────────┘
              │ /run_project
              ▼
┌─────────────────────────────────┐
│ python-ide-sgp1 (existing)      │  Extends code-executor with multi-file
│   firejail sandbox              │  --whitelist=<workspace_dir>
└─────────────────────────────────┘
```

## Phases

- **Phase 0** ✅ Repo scaffold, migrations 01–06, droplet extension draft
- **Phase 1** Cross-subdomain auth (cookie widen on app.english-coding), CM6 editor, single-file load+save
- **Phase 2** File tree CRUD, multi-project, project switcher
- **Phase 3** Runner WSS — stream stdout/stderr from droplet, Run/Stop, runs table
- **Phase 3b** pygbag pipeline for Pygame; static-web iframe srcdoc
- **Phase 4** Hocuspocus live collab, y-codemirror, per-project presence
- **Phase 5** Teacher dashboard — open student IDE, audit log
- **Phase 6** Korean strings sweep, iPad QA, first cohort onboard

## Dev

```bash
pnpm install   # or npm install
cp .env.example .env.local   # fill VITE_SUPABASE_URL etc.
pnpm dev
```

Open `http://localhost:5180/?session=<your_session_token_from_app_login>`
during Phase 0/1 before cross-subdomain cookie ships.

## Migrations

Apply via Supabase Management API, same pattern as app.english-coding:

```bash
for f in scripts/sql/*.sql; do
  echo ">>> $f"
  curl ... # see app.english-coding/scripts/apply.mjs for template
done
```

## Authorization model

- **Student access**: `app_users.feature_flags.ide_enabled = true`
- **Staff access**: `app_users.role IN ('admin','teacher')` OR row in `ide.staff`
- Adding a student: flip the flag. That's it. No cohort / class roster.

## Repo

Private. Owner: `datawithkasim/english-coding-ide`.
