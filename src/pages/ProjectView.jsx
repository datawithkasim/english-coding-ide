import { useEffect, useMemo, useRef, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import Editor from '../components/Editor.jsx';
import { supabase, getSessionToken } from '../lib/supabase.js';

const AUTOSAVE_DEBOUNCE_MS = 800;

export default function ProjectView() {
  const { projectId } = useParams();
  const [project, setProject] = useState(null);
  const [files, setFiles] = useState([]);
  const [activeFileId, setActiveFileId] = useState(null);
  const [activeFile, setActiveFile] = useState(null); // {id, path, content_text, version}
  const [saveState, setSaveState] = useState('idle'); // 'idle' | 'saving' | 'saved' | 'error' | 'conflict'
  const [error, setError] = useState(null);
  const saveTimer = useRef(null);
  const pendingContent = useRef(null);

  // Load project + file index
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const token = getSessionToken();
      const { data, error } = await supabase.rpc('ide_get_project', {
        p_session_token: token,
        p_project_id: projectId,
      });
      if (cancelled) return;
      if (error) {
        setError(error.message);
        return;
      }
      setProject(data.project);
      setFiles(data.files);
      // Auto-open the entrypoint (first matching path), else first file
      const entryFile = data.files.find((f) => f.path === data.project.entrypoint) ?? data.files[0];
      if (entryFile) setActiveFileId(entryFile.id);
    })();
    return () => {
      cancelled = true;
    };
  }, [projectId]);

  // Load active file content
  useEffect(() => {
    if (!activeFileId) return;
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

  // Debounced autosave triggered by editor onChange
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
      // Bump local version + content to stay in sync for next save
      setActiveFile((prev) => prev && { ...prev, content_text: content, version: data.version });
      setSaveState('saved');
    }, AUTOSAVE_DEBOUNCE_MS);
  };

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
            disabled
            title="Phase 3"
            className="px-3 py-1 rounded bg-slate-800 text-slate-500 text-sm font-medium cursor-not-allowed"
          >
            ▶ Run
          </button>
        </div>
      </header>
      <div className="flex-1 grid grid-cols-[16rem_1fr] min-h-0">
        <aside className="border-r border-slate-800 p-3 text-sm overflow-y-auto">
          <div className="text-xs uppercase tracking-wider text-slate-500 mb-2">Files</div>
          <ul className="space-y-1">
            {files.map((f) => (
              <li key={f.id}>
                <button
                  onClick={() => setActiveFileId(f.id)}
                  className={`w-full text-left px-2 py-1 rounded font-mono text-xs ${
                    f.id === activeFileId
                      ? 'bg-brand-accent/20 text-brand-accent'
                      : 'text-slate-300 hover:bg-slate-800'
                  }`}
                >
                  {f.path}
                </button>
              </li>
            ))}
          </ul>
          <div className="mt-4 text-xs text-slate-600">
            File tree CRUD ships in Phase 2.
          </div>
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
      </div>
    </div>
  );
}
