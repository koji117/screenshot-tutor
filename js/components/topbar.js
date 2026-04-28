// js/components/topbar.js
// Top bar: app title + model picker + lang toggle + history toggle.

import { getSettings, setSettings } from '../store.js';
import { t } from '../i18n.js';

export function mountTopbar(container, { onNewSession, onToggleHistory }) {
  const s = getSettings();
  container.innerHTML = `
    <header class="topbar">
      <div class="topbar-title">${t('app.title', s.lang)}</div>
      <div class="topbar-actions">
        <button id="tb-new" type="button">${t('topbar.new', s.lang)}</button>
        <label>
          <span class="topbar-label">${t('topbar.model', s.lang)}</span>
          <select id="tb-model">
            <option value="e2b" ${s.model === 'e2b' ? 'selected' : ''}>e2b</option>
            <option value="e4b" ${s.model === 'e4b' ? 'selected' : ''}>e4b</option>
          </select>
        </label>
        <label>
          <span class="topbar-label">${t('topbar.lang', s.lang)}</span>
          <select id="tb-lang">
            <option value="en" ${s.lang === 'en' ? 'selected' : ''}>EN</option>
            <option value="ja" ${s.lang === 'ja' ? 'selected' : ''}>JA</option>
          </select>
        </label>
        <button id="tb-history" type="button">${t('topbar.history', s.lang)}</button>
      </div>
    </header>
  `;

  function emit(detail) {
    container.dispatchEvent(new CustomEvent('topbar-change', { detail }));
  }

  container.querySelector('#tb-model').addEventListener('change', (e) => {
    setSettings({ model: e.target.value });
    emit({ key: 'model', value: e.target.value });
  });

  container.querySelector('#tb-lang').addEventListener('change', (e) => {
    setSettings({ lang: e.target.value });
    mountTopbar(container, { onNewSession, onToggleHistory });
    emit({ key: 'lang', value: e.target.value });
  });

  container.querySelector('#tb-new').addEventListener('click', () => {
    if (onNewSession) onNewSession();
  });

  container.querySelector('#tb-history').addEventListener('click', () => {
    if (onToggleHistory) onToggleHistory();
  });
}
