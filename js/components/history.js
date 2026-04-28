// js/components/history.js
// Slide-in left drawer that lists past sessions. Click to load. Delete per-row.

import { getSessions, deleteSession, getSettings, setSettings } from '../store.js';
import { t } from '../i18n.js';

export function mountHistory(container, { onSelect }) {
  const s = getSettings();
  let isOpen = !!s.historyOpen;

  function render() {
    const sessions = getSessions();
    container.innerHTML = `
      <aside class="history ${isOpen ? 'open' : ''}">
        <div class="history-header">
          <h3>${t('topbar.history', s.lang)}</h3>
          <button id="history-close" type="button" aria-label="Close">×</button>
        </div>
        <div class="history-list">
          ${sessions.length === 0
            ? `<p class="muted" style="padding:1rem">${t('history.empty', s.lang)}</p>`
            : sessions.map((sess) => `
                <div class="history-item" data-id="${sess.id}">
                  <img src="${sess.imageThumb || sess.image}" alt="">
                  <div class="history-item-body">
                    <div class="history-item-summary">${(sess.summary || '').slice(0, 80) || '(generating…)'}</div>
                    <div class="history-item-time muted">${new Date(sess.createdAt).toLocaleString()}</div>
                  </div>
                  <button class="history-delete" data-delete="${sess.id}" type="button" aria-label="Delete">×</button>
                </div>
              `).join('')}
        </div>
      </aside>
    `;

    container.querySelector('#history-close').addEventListener('click', () => toggle(false));

    container.querySelectorAll('.history-item').forEach((node) => {
      node.addEventListener('click', (e) => {
        if (e.target.closest('.history-delete')) return;
        const id = node.getAttribute('data-id');
        if (id && onSelect) onSelect(id);
        toggle(false);
      });
    });

    container.querySelectorAll('.history-delete').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.getAttribute('data-delete');
        if (id && confirm(t('history.confirmDelete', s.lang))) {
          deleteSession(id);
          render();
        }
      });
    });
  }

  function toggle(next) {
    isOpen = next === undefined ? !isOpen : !!next;
    setSettings({ historyOpen: isOpen });
    render();
  }

  render();

  return {
    open: () => toggle(true),
    close: () => toggle(false),
    toggle: () => toggle(),
    refresh: render,
  };
}
