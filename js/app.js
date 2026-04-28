// js/app.js
// App bootstrap. Wires topbar + history drawer + empty state + session.
import { mountTopbar } from './components/topbar.js';
import { mountEmptyState } from './components/empty-state.js';
import { mountSession } from './components/session.js';
import { mountSynthesis } from './components/synthesis.js';
import { mountHistory } from './components/history.js';
import { addSession } from './store.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div id="topbar-root"></div>
  <div id="history-root"></div>
  <main class="main" id="main-root"></main>
`;

const main = document.getElementById('main-root');

function showToast(message, kind) {
  const el = document.createElement('div');
  el.className = 'toast' + (kind ? ' toast-' + kind : '');
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.classList.add('show'), 10);
  setTimeout(() => {
    el.classList.remove('show');
    setTimeout(() => el.remove(), 300);
  }, 4000);
}

// Expose toast helper for components without threading it through props.
window.__showToast = showToast;

// Bump WORKER_VERSION when js/worker.js or its imports change in a way
// that needs a fresh fetch. Browsers cache the Worker script separately
// from the page, so a plain Cmd+Shift+R won't necessarily pick up a new
// worker.js — adding ?v=N forces the browser to treat it as a new URL.
const WORKER_VERSION = 3;

let worker = createWorker();

function createWorker() {
  const url = new URL('./worker.js', import.meta.url);
  url.searchParams.set('v', String(WORKER_VERSION));
  const w = new Worker(url, { type: 'module' });
  w.onerror = (e) => {
    console.error('worker error:', e);
    showToast('Worker crashed; respawning. Click New to retry.', 'error');
    try { w.terminate(); } catch {}
    setTimeout(() => { worker = createWorker(); }, 200);
  };
  return w;
}

let activeSessionMount = null;
let activeEmptyMount = null;
let activeSynthesisMount = null;

function clearActiveMounts() {
  if (activeSessionMount) { activeSessionMount.destroy(); activeSessionMount = null; }
  if (activeEmptyMount) { activeEmptyMount.destroy(); activeEmptyMount = null; }
  if (activeSynthesisMount) { activeSynthesisMount.destroy(); activeSynthesisMount = null; }
}

function showEmpty() {
  clearActiveMounts();
  main.innerHTML = '';
  activeEmptyMount = mountEmptyState(main, {
    onImage: (result) => {
      const session = addSession({
        image: result.image,
        imageThumb: result.thumb,
      });
      historyMount.refresh();
      showSession(session.id);
    },
    onError: (err) => showToast(err, 'error'),
  });
}

function showSession(sessionId) {
  clearActiveMounts();
  main.innerHTML = '';
  activeSessionMount = mountSession(main, { worker, sessionId });
}

function showSynthesis() {
  clearActiveMounts();
  main.innerHTML = '';
  activeSynthesisMount = mountSynthesis(main, {
    worker,
    onAfterClear: () => historyMount.refresh(),
  });
}

const historyMount = mountHistory(document.getElementById('history-root'), {
  onSelect: (id) => showSession(id),
  onSynthesize: showSynthesis,
});

mountTopbar(document.getElementById('topbar-root'), {
  onNewSession: showEmpty,
  onToggleHistory: () => historyMount.toggle(),
});

showEmpty();
