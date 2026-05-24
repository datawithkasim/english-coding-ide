import { useEffect, useMemo, useRef, useState } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import Editor from '../components/Editor.jsx';
import OutputPanel from '../components/OutputPanel.jsx';
import { supabase, getSessionToken } from '../lib/supabase.js';
import { runProject } from '../lib/runner.js';

const AUTOSAVE_DEBOUNCE_MS = 800;

export default function ProjectView() {
  const { projectId } = useParams();
  const navigate = useNavigate();
  const [project, setProject] = useState(null);
  const [files, setFiles] = useState([]);
  const [activeFileId, setActiveFileId] = useState(null);
  const [activeFile, setActiveFile] = useState(null);
  const [saveState, setSaveState] = useState('idle');
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [running, setRunning] = useState(false);
  const [runResult, setRunResult] = useState(null);
  const saveTimer = useRef(null);
  const pendingContent = useRef(null);

  async function loadProject(preferredFileId) {
    const token = getSessionToken();
    const { data, error } = await supabase.rpc('ide_get_project', {
      p_session_token: token,
      p_project_id: projectId,
    });
    if (error) {
      setError(error.message);
      return;
    }
    setProject(data.project);
    setFiles(data.files);
    if (preferredFileId && data.files.some((f) => f.id === preferredFileId)) {
      setActiveFileId(preferredFileId);
    } else {
      const entry = data.files.find((f) => f.path === data.project.entrypoint) ?? data.files[0];
      setActiveFileId(entry ? entry.id : null);
    }
  }

  useEffect(() => {
    loadProject();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectId]);

  useEffect(() => {
    if (!activeFileId) {
      setActiveFile(null);
      return;
    }
    let cancelled = false;
    (async () => {
      const token = getSessionToken();
      const { data, error } = await supabase.rpc('ide_get_file', {
        p_session_token: token,
        p_file_id: activeFileId,
      });
      if (cancelled) return;
      if (error) {
        setError(error.message);
        return;
      }
      setActiveFile(data);
      setSaveState('idle');
    })();
    return () => {
      cancelled = true;
    };
  }, [activeFileId]);

  const handleEditorChange = (newContent) => {
    if (!activeFile) return;
    pendingContent.current = newContent;
    setSaveState('saving');
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      const token = getSessionToken();
      const content = pendingContent.current;
      const { data, error } = await supabase.rpc('ide_save_file', {
        p_session_token: token,
        p_file_id: activeFile.id,
        p_content_text: content,
        p_expected_version: activeFile.version,
        p_kind: 'auto_save',
      });
      if (error) {
        if (String(error.message).includes('ide_version_conflict')) {
          setSaveState('conflict');
        } else {
          setSaveState('error');
          setError(error.message);
        }
        return;
      }
      setActiveFile((prev) => prev && { ...prev, content_text: content, version: data.version });
      setSaveState('saved');
    }, AUTOSAVE_DEBOUNCE_MS);
  };

  async function handleNewFile() {
    const path = window.prompt('New file path? (e.g. lib/utils.py)');
    if (!path) return;
    setBusy(true);
    setError(null);
    const token = getSessionToken();
    const { data, error } = await supabase.rpc('ide_create_file', {
      p_session_token: token,
      p_project_id: projectId,
      p_path: path,
      p_content_text: '',
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    await loadProject(data.id);
  }

  async function handleRenameFile(file) {
    const newPath = window.prompt(`Rename ${file.path} to:`, file.path);
    if (!newPath || newPath === file.path) return;
    setBusy(true);
    setError(null);
    const token = getSessionToken();
    const { error } = await supabase.rpc('ide_rename_file', {
      p_session_token: token,
      p_file_id: file.id,
      p_new_path: newPath,
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    await loadProject(file.id);
  }

  async function handleDeleteFile(file) {
    if (!window.confirm(`Delete ${file.path}?`)) return;
    setBusy(true);
    setError(null);
    const token = getSessionToken();
    const { error } = await supabase.rpc('ide_delete_file', {
      p_session_token: token,
      p_file_id: file.id,
    });
    setBusy(false);
    if (error) {
      setError(error.message);
      return;
    }
    const remaining = files.filter((f) => f.id !== file.id);
    await loadProject(remaining[0]?.id);
  }

  async function handleRun() {
    if (!project || running) return;
    // Flush any pending autosave before running so the droplet sees latest content
    if (saveTimer.current && activeFile && pendingContent.current !== null) {
      clearTimeout(saveTimer.current);
      const token = getSessionToken();
      const content = pendingContent.current;
      const { data, error } = await supabase.rpc('ide_save_file', {
        p_session_token: token,
        p_file_id: activeFile.id,
        p_content_text: content,
        p_expected_version: activeFile.version,
        p_kind: 'manual_save',
      });
      if (!error) {
        setActiveFile((prev) => prev && { ...prev, content_text: content, version: data.version });
        setSaveState('saved');
      }
    }

    setRunning(true);
    setRunResult(null);
    // Refetch file contents for the runner — autosave may not have flushed all tabs
    const token = getSessionToken();
    const { data: proj, error: projErr } = await supabase.rpc('ide_get_project', {
      p_session_token: token,
      p_project_id: projectId,
    });
    if (projErr) {
      setRunResult({ status: 'infra_error', exitCode: 1, stdout: '', stderr: projErr.message, duration: 0 });
      setRunning(false);
      return;
    }
    const allFiles = await Promise.all(
      proj.files.map(async (f) => {
        const { data, error } = await supabase.rpc('ide_get_file', {
          p_session_token: token,
          p_file_id: f.id,
        });
        return error ? null : { path: f.path, content_text: data.content_text };
      })
    );
    const validFiles = allFiles.filter(Boolean);

    const result = await runProject({
      projectId,
      runtime: project.runtime,
      entrypoint: project.entrypoint,
      files: validFiles,
    });
    setRunResult(result);
    setRunning(false);
  }

  async function handleArchiveProject() {
    if (!window.confirm(`Archive "${project?.name}"? You can restore it later.`)) return;
    const token = getSessionToken();
    const { error } = await supabase.rpc('ide_archive_project', {
      p_session_token: token,
      p_project_id: projectId,
      p_archive: true,
    });
    if (error) {
      setError(error.message);
      return;
    }
    navigate('/');
  }

  const editorLanguage = useMemo(() => {
    if (!activeFile) return 'python';
    if (activeFile.path.endsWith('.js')) return 'javascript';
    return 'python';
  }, [activeFile]);

  if (error && !project) {
    return (
      <div className="p-8">
        <Link to="/" className="text-sm text-brand-accent">← Back</Link>
        <div className="mt-4 text-red-300">{error}</div>
      </div>
    );
  }

  if (!project) {
    return <div className="p-8 text-slate-400">Loading project…</div>;
  }

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-slate-800 px-4 py-2 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <Link to="/" className="text-sm text-slate-400 hover:text-brand-accent">←</Link>
          <div className="font-medium">{project.name}</div>
          <div className="font-mono text-xs text-slate-500">{project.runtime}</div>
        </div>
        <div className="flex items-center gap-3 text-xs">
          <span className={{
            idle: 'text-slate-500',
            saving: 'text-amber-400',
            saved: 'text-emerald-400',
            error: 'text-red-400',
            conflict: 'text-orange-400',
          }[saveState]}>
            {{
              idle: '',
              saving: 'Saving…',
              saved: 'Saved',
              error: 'Save failed',
              conflict: 'Out of date — reload',
            }[saveState]}
          </span>
          <button
            onClick={handleArchiveProject}
            className="px-2 py-1 rounded border border-slate-700 text-slate-400 text-xs hover:border-red-500/50 hover:text-red-300"
          >
            Archive
          </button>
          <button
            onClick={handleRun}
            disabled={running}
            className="px-3 py-1 rounded bg-brand-accent text-slate-950 text-sm font-medium disabled:opacity-50"
          >
            {running ? 'Running…' : '▶ Run'}
          </button>
        </div>
      </header>

      {error && (
        <div className="mx-4 mt-2 p-2 rounded border border-red-500/40 bg-red-500/10 text-red-300 text-xs">
          {error}
        </div>
      )}

      <div className="flex-1 grid grid-cols-[16rem_1fr_24rem] min-h-0">
        <aside className="border-r border-slate-800 p-3 text-sm overflow-y-auto">
          <div className="flex items-center justify-between mb-2">
            <div className="text-xs uppercase tracking-wider text-slate-500">Files</div>
            <button
              onClick={handleNewFile}
              disabled={busy}
              className="text-xs px-2 py-0.5 rounded bg-brand-accent/15 text-brand-accent hover:bg-brand-accent/25 disabled:opacity-50"
            >
              + New
            </button>
          </div>
          <ul className="space-y-1">
            {files.map((f) => (
              <li key={f.id} className="group flex items-center gap-1">
                <button
                  onClick={() => setActiveFileId(f.id)}
                  className={`flex-1 text-left px-2 py-1 rounded font-mono text-xs truncate ${
                    f.id === activeFileId
                      ? 'bg-brand-accent/20 text-brand-accent'
                      : 'text-slate-300 hover:bg-slate-800'
                  }`}
                  title={f.path}
                >
                  {f.path}
                  {f.path === project.entrypoint && (
                    <span className="ml-1 text-[10px] text-amber-400/70" title="Entrypoint">▶</span>
                  )}
                </button>
                <button
                  onClick={() => handleRenameFile(f)}
                  className="opacity-0 group-hover:opacity-100 text-xs text-slate-500 hover:text-slate-300 px-1"
                  title="Rename"
                >
                  ✎
                </button>
                {f.path !== project.entrypoint && (
                  <button
                    onClick={() => handleDeleteFile(f)}
                    className="opacity-0 group-hover:opacity-100 text-xs text-slate-500 hover:text-red-400 px-1"
                    title="Delete"
                  >
                    ×
                  </button>
                )}
              </li>
            ))}
          </ul>
        </aside>
        <main className="min-h-0">
          {activeFile ? (
            <Editor
              key={activeFile.id}
              value={activeFile.content_text ?? ''}
              language={editorLanguage}
              onChange={handleEditorChange}
            />
          ) : (
            <div className="p-8 text-slate-500">Select a file</div>
          )}
        </main>
        <aside className="border-l border-slate-800 min-h-0">
          <OutputPanel result={runResult} running={running} />
        </aside>
      </div>
    </div>
  );
}
