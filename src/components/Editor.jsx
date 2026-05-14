import { useEffect, useRef } from 'react';
import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { python } from '@codemirror/lang-python';
import { javascript } from '@codemirror/lang-javascript';
import { oneDark } from '@codemirror/theme-one-dark';

export default function Editor({ value, language = 'python', onChange }) {
  const hostRef = useRef(null);
  const viewRef = useRef(null);

  useEffect(() => {
    if (!hostRef.current) return;
    const lang = language === 'javascript' ? javascript() : python();
    const state = EditorState.create({
      doc: value ?? '',
      extensions: [
        basicSetup,
        lang,
        oneDark,
        EditorView.updateListener.of((u) => {
          if (u.docChanged && onChange) onChange(u.state.doc.toString());
        }),
      ],
    });
    const view = new EditorView({ state, parent: hostRef.current });
    viewRef.current = view;
    return () => view.destroy();
  }, [language]);

  return <div ref={hostRef} className="h-full" />;
}
