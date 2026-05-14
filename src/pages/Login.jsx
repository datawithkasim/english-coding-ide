export default function Login() {
  const appUrl = import.meta.env.VITE_APP_URL ?? 'https://app.english-coding.co.uk';
  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="max-w-md text-center space-y-6">
        <h1 className="text-3xl font-semibold">English Coding Lab</h1>
        <p className="text-slate-400">
          Sign in at app.english-coding.co.uk first, then return here.
        </p>
        <a
          href={appUrl}
          className="inline-block px-6 py-3 rounded-lg bg-brand-accent text-slate-950 font-medium hover:bg-cyan-300"
        >
          Go to login
        </a>
      </div>
    </div>
  );
}
