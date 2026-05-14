export default function Dashboard() {
  return (
    <div className="min-h-screen p-8">
      <header className="flex items-center justify-between mb-8">
        <h1 className="text-2xl font-semibold">My Projects</h1>
        <button className="px-4 py-2 rounded bg-brand-accent text-slate-950 font-medium">
          + New project
        </button>
      </header>
      <div className="text-slate-400">
        Phase 0 — Dashboard skeleton. Project list ships in Phase 2.
      </div>
    </div>
  );
}
