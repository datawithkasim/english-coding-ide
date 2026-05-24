import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase, getSessionToken } from '../lib/supabase.js';

export default function Dashboard() {
  const navigate = useNavigate();
  const [projects, setProjects] = useState(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState(null);

  async function refresh() {
    const token = getSessionToken();
    const { data, error } = await supabase.rpc('ide_list_projects', { p_session_token: token });
    if (error) {
      setError(error.message);
      setProjects([]);
      return;
    }
    setProjects(data ?? []);
  }

  useEffect(() => {
    refresh();
  }, []);

  async function handleNew() {
    const name = window.prompt('Project name?');
    if (!name) return;
    setCreating(true);
    setError(null);
    const token = getSessionToken();
    const { data, error } = await supabase.rpc('ide_create_project', {
      p_session_token: token,
      p_name: name,
      p_runtime: 'python',
    });
    setCreating(false);
    if (error) {
      setError(error.message);
      return;
    }
    navigate(`/p/${data}`);
  }

  return (
    <div className="min-h-screen p-8">
      <header className="flex items-center justify-between mb-8">
        <h1 className="text-2xl font-semibold">My Projects</h1>
        <button
          onClick={handleNew}
          disabled={creating}
          className="px-4 py-2 rounded bg-brand-accent text-slate-950 font-medium disabled:opacity-50"
        >
          {creating ? 'Creating…' : '+ New project'}
        </button>
      </header>

      {error && (
        <div className="mb-4 p-3 rounded border border-red-500/40 bg-red-500/10 text-red-300 text-sm">
          {error}
        </div>
      )}

      {projects === null ? (
        <div className="text-slate-400">Loading…</div>
      ) : projects.length === 0 ? (
        <div className="text-slate-400">
          No projects yet. Click <strong>+ New project</strong> to start.
        </div>
      ) : (
        <ul className="grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
          {projects.map((p) => (
            <li key={p.id}>
              <Link
                to={`/p/${p.id}`}
                className="block p-4 rounded border border-slate-800 hover:border-brand-accent transition"
              >
                <div className="font-medium">{p.name}</div>
                <div className="text-xs text-slate-500 font-mono mt-1">
                  {p.runtime} · {p.entrypoint}
                </div>
                <div className="text-xs text-slate-600 mt-2">
                  Updated {new Date(p.updated_at).toLocaleString()}
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
