export default function OutputPanel({ result, running }) {
  if (running) {
    return (
      <div className="h-full p-3 font-mono text-xs text-amber-300 overflow-y-auto">
        Running…
      </div>
    );
  }
  if (!result) {
    return (
      <div className="h-full p-3 font-mono text-xs text-slate-600 overflow-y-auto">
        Press ▶ Run to execute. Output appears here.
      </div>
    );
  }
  const statusColor = {
    completed: 'text-emerald-400',
    failed: 'text-red-400',
    timeout: 'text-orange-400',
    killed: 'text-slate-400',
    infra_error: 'text-red-500',
  }[result.status] ?? 'text-slate-400';

  return (
    <div className="h-full overflow-y-auto p-3 font-mono text-xs">
      <div className={`mb-2 text-[11px] uppercase tracking-wider ${statusColor}`}>
        {result.status} · exit {result.exitCode} · {result.duration}ms
      </div>
      {result.stdout && (
        <pre className="whitespace-pre-wrap text-slate-200">{result.stdout}</pre>
      )}
      {result.stderr && (
        <pre className="whitespace-pre-wrap text-red-300 mt-2">{result.stderr}</pre>
      )}
      {!result.stdout && !result.stderr && (
        <div className="text-slate-500">(no output)</div>
      )}
    </div>
  );
}
