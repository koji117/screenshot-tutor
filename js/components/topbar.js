// js/components/topbar.js
// Top bar: app title + model picker + lang toggle + history toggle.

import { getSettings, setSettings } from '../store.js';
import { MODELS, MODEL_IDS } from '../models.js';
import { t } from '../i18n.js';

function formatSize(mb) {
  if (mb >= 1000) return (mb / 1000).toFixed(mb % 1000 === 0 ? 0 : 1) + 'GB';
  return mb + 'MB';
}

function modelOptions(selectedId) {
  return MODEL_IDS.map((id) => {
    const m = MODELS[id];
    return `<option value="${id}"${id === selectedId ? ' selected' : ''}>${m.label} (${formatSize(m.sizeMB)})</option>`;
  }).join('');
}

export function mountTopbar(container, { onNewSession, onToggleHistory, onModelChange }) {
  const s = getSettings();
  container.innerHTML = `
    <header class="topbar">
      <div class="topbar-title">${t('app.title', s.lang)}</div>
      <div class="topbar-actions">
        <button id="tb-new" type="button">${t('topbar.new', s.lang)}</button>
        <label>
          <span class="topbar-label">${t('topbar.model', s.lang)}</span>
          <select id="tb-model">
            ${modelOptions(s.model)}
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
    if (onModelChange) onModelChange(e.target.value);
  });

  container.querySelector('#tb-lang').addEventListener('change', (e) => {
    setSettings({ lang: e.target.value });
    mountTopbar(container, { onNewSession, onToggleHistory, onModelChange });
    emit({ key: 'lang', value: e.target.value });
  });

  container.querySelector('#tb-new').addEventListener('click', () => {
    if (onNewSession) onNewSession();
  });

  container.querySelector('#tb-history').addEventListener('click', () => {
    if (onToggleHistory) onToggleHistory();
  });
}
