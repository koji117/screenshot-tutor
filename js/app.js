// js/app.js
// App bootstrap. Wires topbar + empty state + session.
import { mountTopbar } from './components/topbar.js';
import { mountEmptyState } from './components/empty-state.js';
import { mountSession } from './components/session.js';
import { addSession } from './store.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div id="topbar-root"></div>
  <main class="main" id="main-root"></main>
`;

const main = document.getElementById('main-root');
const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
worker.onerror = (e) => console.error('worker error:', e);

let activeSessionMount = null;
let activeEmptyMount = null;

function showEmpty() {
  if (activeSessionMount) { activeSessionMount.destroy(); activeSessionMount = null; }
  main.innerHTML = '';
  activeEmptyMount = mountEmptyState(main, {
    onImage: (result) => {
      const session = addSession({
        image: result.image,
        imageThumb: result.thumb,
      });
      showSession(session.id);
    },
  });
}

function showSession(sessionId) {
  if (activeEmptyMount) { activeEmptyMount.destroy(); activeEmptyMount = null; }
  if (activeSessionMount) { activeSessionMount.destroy(); }
  main.innerHTML = '';
  activeSessionMount = mountSession(main, { worker, sessionId });
}

mountTopbar(document.getElementById('topbar-root'), {
  onNewSession: showEmpty,
  onToggleHistory: () => alert('history drawer comes in a later task'),
});

showEmpty();
