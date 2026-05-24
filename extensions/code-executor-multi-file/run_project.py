"""Multi-file project execution endpoint for python-ide-sgp1.

Append this to app.english-coding/code-executor/main.py during Phase 3 deploy.
Reuses the existing firejail sandbox config from run_code() — only difference
is workspace dir vs single tempfile, and --whitelist points at the dir.

Wire-up:
  1. Add the WorkspaceFile + RunProjectRequest models near ExecuteRequest.
  2. Add the run_workspace() helper near run_code().
  3. Add the /run_project route below /execute.
  4. scp updated main.py to droplet → `systemctl restart code-executor`.
  5. Smoke test with the curl block at the bottom of this file.

Auth: same validate_session_token() gate as /execute (Phase 88).
Path safety: workspace files are checked against `_safe_workspace_path()`
so a student can't write `../../../etc/passwd` even before firejail confines.
"""

# ────────────────────────────────────────────────────────────────────
# Models (paste near ExecuteRequest)
# ────────────────────────────────────────────────────────────────────

# class WorkspaceFile(BaseModel):
#     path: str                         # POSIX-style relative path, e.g. "main.py"
#     content_text: Optional[str] = None
#     content_b64: Optional[str] = None

# class RunProjectRequest(BaseModel):
#     project_id: str
#     entrypoint: str                   # path within workspace, e.g. "main.py"
#     runtime: str = "python"           # "python" | "javascript"
#     files: list[WorkspaceFile]
#     stdin: Optional[str] = ""
#     session_token: Optional[str] = None


# ────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────

import os
import re
import shutil
import subprocess
import tempfile
from typing import Optional

# Allow only safe filename chars + forward slashes for subdirs.
_SAFE_PATH = re.compile(r"^[A-Za-z0-9_./-]+$")


def _safe_workspace_path(path: str) -> bool:
    if not path or len(path) > 256:
        return False
    if path.startswith("/") or ".." in path.split("/"):
        return False
    return bool(_SAFE_PATH.match(path))


def run_workspace(
    files,                    # list[WorkspaceFile]
    entrypoint: str,
    runtime: str = "python",
    stdin: str = "",
    timeout: int = None,      # default: reuse TIMEOUT_SECONDS from main.py
):
    """Materialize files in a tempdir, exec entrypoint inside firejail.

    Reuses /execute's sandbox flags but swaps `--whitelist=<single file>`
    for `--whitelist=<workspace_dir>`. Everything else is identical, so the
    security envelope is unchanged.

    Timeout note: defaults to the module-level TIMEOUT_SECONDS used by the
    single-file /execute route. Multi-file projects don't take longer than
    single-file ones at the same code length — student code runs at the same
    speed either way — so there's no justification for a higher cap. Keeping
    them in lockstep also avoids one route starving the single-worker
    uvicorn instance more than the other.
    """
    if timeout is None:
        timeout = TIMEOUT_SECONDS
    if not _safe_workspace_path(entrypoint):
        return "", "Error: invalid entrypoint path", 1

    workdir = tempfile.mkdtemp(prefix="ec_ws_", dir="/tmp")
    try:
        for f in files:
            if not _safe_workspace_path(f.path):
                return "", f"Error: invalid file path: {f.path}", 1
            full = os.path.join(workdir, f.path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            # Reject pre-existing symlinks at the target path. Path-string
            # validation rejects `../etc/passwd` but cannot stop a file the
            # student created via prior code (`os.symlink('/etc/passwd', 'leak')`)
            # from leaking arbitrary host files on the next /run_project call.
            # Firejail's `--whitelist=<workdir>` does NOT consistently resolve
            # symlinks against the whitelist, so block at write time.
            if os.path.lexists(full) and os.path.islink(full):
                return "", f"Error: refusing to write through symlink: {f.path}", 1
            if f.content_text is not None:
                with open(full, "w", encoding="utf-8") as fh:
                    fh.write(f.content_text)
            elif f.content_b64 is not None:
                import base64 as _b64
                with open(full, "wb") as fh:
                    fh.write(_b64.b64decode(f.content_b64))

        entry_full = os.path.join(workdir, entrypoint)
        if not os.path.isfile(entry_full):
            return "", f"Error: entrypoint not found: {entrypoint}", 1

        runner = "node" if runtime == "javascript" else "python3"

        # Mirrors run_code() in main.py. The only difference is --whitelist=<dir>.
        sandbox = [
            "firejail",
            "--quiet",
            "--noprofile",
            "--net=none",
            "--private",
            "--private-tmp",
            "--private-dev",
            "--private-etc=ld.so.cache,ld.so.conf,ld.so.conf.d,ssl,ca-certificates,"
            "nsswitch.conf,resolv.conf,hosts,hostname,localtime,alternatives,"
            "passwd,group,locale.conf,locale.alias,default/locale",
            "--env=LANG=C.UTF-8",
            "--env=LC_ALL=C.UTF-8",
            "--env=PYTHONIOENCODING=utf-8",
            "--env=PYTHONUTF8=1",
            "--caps.drop=all",
            "--nonewprivs",
            "--seccomp",
            "--rlimit-cpu=15",
            "--rlimit-nproc=64",
            "--rlimit-fsize=10485760",
            f"--whitelist={workdir}",
        ]

        result = subprocess.run(
            sandbox + [runner, entry_full],
            input=stdin,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=workdir,
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "", f"Error: project execution timed out after {timeout}s", 1
    except FileNotFoundError as e:
        return "", f"Error: sandbox or runtime missing: {e}", 1
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


# ────────────────────────────────────────────────────────────────────
# Route (paste below /execute)
# ────────────────────────────────────────────────────────────────────

# @app.post("/run_project")
# async def run_project(req: RunProjectRequest):
#     # Same auth gate as /execute. No grace.
#     if not await validate_session_token(req.session_token):
#         return JSONResponse(
#             status_code=401,
#             content={"data": {"stdout": "", "stderr": "", "passed": False,
#                               "auth_expired": True}},
#         )
#
#     if not req.files or not 1 <= len(req.files) <= 64:
#         return {"data": {"stdout": "", "stderr": "Error: 1-64 files required",
#                          "exitCode": 1}}
#
#     stdout, stderr, code = run_workspace(
#         files=req.files,
#         entrypoint=req.entrypoint,
#         runtime=(req.runtime or "python").lower(),
#         stdin=req.stdin or "",
#     )
#     return {
#         "data": {
#             "stdout": stdout,
#             "stderr": stderr,
#             "output": stdout,
#             "error": stderr,
#             "exitCode": code,
#             "passed": code == 0,
#             "mode": "project",
#         }
#     }


# ────────────────────────────────────────────────────────────────────
# Smoke test (run from local machine after deploy)
# ────────────────────────────────────────────────────────────────────

# curl -X POST https://<droplet-host>/run_project \
#   -H "Content-Type: application/json" \
#   -d '{
#     "project_id": "test-1",
#     "entrypoint": "main.py",
#     "runtime": "python",
#     "session_token": "<your-app-session-token>",
#     "files": [
#       {"path": "main.py",   "content_text": "from utils import greet\nprint(greet(\"world\"))"},
#       {"path": "utils.py",  "content_text": "def greet(n): return f\"hi {n}\""}
#     ]
#   }'
#
# Expected: {"data":{"stdout":"hi world\n","stderr":"","exitCode":0,"passed":true,...}}
