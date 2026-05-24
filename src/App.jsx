import { useEffect, useState } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { bootstrapSession, supabase } from './lib/supabase.js';
import Login from './pages/Login.jsx';
import Dashboard from './pages/Dashboard.jsx';
import ProjectView from './pages/ProjectView.jsx';

export default function App() {
  const [authState, setAuthState] = useState({ checked: false, hasAccess: false });

  useEffect(() => {
    const token = bootstrapSession();
    if (!token) {
      setAuthState({ checked: true, hasAccess: false });
      return;
    }
    supabase
      .rpc('ide_has_access', { p_session_token: token })
      .then(({ data, error }) => {
        if (error) {
          setAuthState({ checked: true, hasAccess: false });
          return;
        }
        setAuthState({ checked: true, hasAccess: Boolean(data) });
      });
  }, []);

  if (!authState.checked) {
    return <div className="p-8 text-slate-400">Loading…</div>;
  }

  if (!authState.hasAccess) {
    return (
      <Routes>
        <Route path="*" element={<Login />} />
      </Routes>
    );
  }

  return (
    <Routes>
      <Route path="/" element={<Dashboard />} />
      <Route path="/p/:projectId" element={<ProjectView />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
