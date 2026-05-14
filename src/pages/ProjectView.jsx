import { useParams } from 'react-router-dom';
import Editor from '../components/Editor.jsx';

export default function ProjectView() {
  const { projectId } = useParams();
  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-slate-800 px-4 py-2 flex items-center justify-between">
        <div className="font-mono text-sm text-slate-400">project: {projectId}</div>
        <button className="px-3 py-1 rounded bg-brand-accent text-slate-950 text-sm font-medium">
          ▶ Run
        </button>
      </header>
      <div className="flex-1 grid grid-cols-[16rem_1fr_24rem] min-h-0">
        <aside className="border-r border-slate-800 p-4 text-slate-400 text-sm">File tree (Phase 2)</aside>
        <main className="min-h-0">
          <Editor
            value={'# Welcome to English Coding Lab\nprint("hello, world")\n'}
            language="python"
            onChange={() => {}}
          />
        </main>
        <aside className="border-l border-slate-800 p-4 text-slate-400 text-sm">Output (Phase 3)</aside>
      </div>
    </div>
  );
}
