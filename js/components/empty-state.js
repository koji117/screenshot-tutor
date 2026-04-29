// js/components/empty-state.js
// Initial paste/drop/pick zone. Visible when no session is active.
// Also hosts a "Load model" affordance so the user can pre-warm the
// chosen model before picking a file — saves the awkward "first
// request blocks for several minutes" UX on a fresh load.

import { installInputHandlers, captureScreen } from '../input.js';
import { t, tFmt } from '../i18n.js';
import { getSettings } from '../store.js';
import { MODELS } from '../models.js';

function formatSize(mb) {
  if (mb >= 1000) return (mb / 1000).toFixed(mb % 1000 === 0 ? 0 : 1) + 'GB';
  return mb + 'MB';
}

export function mountEmptyState(container, { worker, onImage, onError, getModelStatus, setModelStatus }) {
  const s = getSettings();
  const supportsWebGPU = 'gpu' in navigator;
  const meta = MODELS[s.model] || null;
  const initialStatus = getModelStatus ? getModelStatus(s.model) : 'idle';

  container.innerHTML = `
    <div class="empty" id="empty-zone" tabindex="0">
      <h2>${t('empty.heading', s.lang)}</h2>
      <p class="muted">${t('empty.hint', s.lang)}</p>
      <div class="empty-actions">
        <button id="empty-pick" type="button">${t('empty.pick', s.lang)}</button>
        <button id="empty-capture" type="button">${t('empty.capture', s.lang)}</button>
      </div>
      ${meta ? `
        <div class="empty-model" id="empty-model">
          <div class="empty-model-row">
            <span class="empty-model-label">${t('empty.modelLabel', s.lang)}</span>
            <span class="empty-model-name">${meta.label}</span>
            <span class="muted">· ${formatSize(meta.sizeMB)}</span>
          </div>
          <div class="empty-model-note muted">${meta.note || ''}</div>
          <div class="empty-model-controls">
            <button id="empty-load" type="button" class="primary">${t('empty.loadModel', s.lang)}</button>
            <span id="empty-load-status" class="muted"></span>
          </div>
        </div>
      ` : ''}
      ${!supportsWebGPU
        ? `<p class="error">${t('empty.webgpuRequired', s.lang)}</p>`
        : ''}
      <div id="empty-msg" class="muted"></div>
    </div>
  `;

  const zone = container.querySelector('#empty-zone');
  const msg = container.querySelector('#empty-msg');
  const loadBtn = container.querySelector('#empty-load');
  const loadStatus = container.querySelector('#empty-load-status');

  const handlers = installInputHandlers(
    zone,
    (result) => onImage(result),
    (err) => {
      msg.textContent = err;
      if (onError) onError(err);
    },
  );

  container.querySelector('#empty-pick').addEventListener('click', () => handlers.pickFile());

  container.querySelector('#empty-capture').addEventListener('click', async () => {
    msg.textContent = '';
    try {
      const result = await captureScreen();
      if (!result) {
        msg.textContent = 'capture cancelled';
        return;
      }
      onImage(result);
    } catch (err) {
      msg.textContent = 'capture failed: ' + (err.message || err);
      if (onError) onError(err.message || String(err));
    }
  });

  // --- Pre-load button -----------------------------------------------------

  function applyStatus(status, pct) {
    if (!loadBtn || !loadStatus) return;
    if (status === 'loading') {
      loadBtn.disabled = true;
      loadBtn.textContent = t('empty.loadingModel', s.lang);
      loadStatus.textContent = pct != null
        ? tFmt('session.loading', s.lang, { pct })
        : '';
    } else if (status === 'ready') {
      loadBtn.disabled = true;
      loadBtn.textContent = t('empty.modelReady', s.lang);
      loadStatus.textContent = '';
    } else if (status === 'error') {
      loadBtn.disabled = false;
      loadBtn.textContent = t('empty.retryLoad', s.lang);
      loadStatus.textContent = '';
    } else {
      loadBtn.disabled = false;
      loadBtn.textContent = t('empty.loadModel', s.lang);
      loadStatus.textContent = '';
    }
  }

  applyStatus(initialStatus);

  function onWorkerMessage(e) {
    const m = e.data;
    // Pre-load doesn't have a requestId, so we listen specifically for
    // bare 'loading'/'ready'/'error' that aren't tied to a generation.
    if (!loadBtn) return;
    if (m.type === 'loading') {
      if (loadBtn.disabled) {
        // Already in loading state — just update progress.
        loadStatus.textContent = tFmt('session.loading', s.lang, { pct: m.pct });
      }
    } else if (m.type === 'ready' && m.requestId == null) {
      applyStatus('ready');
      if (setModelStatus) setModelStatus(s.model, 'ready');
    } else if (m.type === 'error' && m.requestId == null) {
      applyStatus('error');
      if (setModelStatus) setModelStatus(s.model, 'error');
      msg.textContent = 'failed to load model: ' + (m.error || '');
    }
  }

  if (worker) worker.addEventListener('message', onWorkerMessage);

  if (loadBtn) {
    loadBtn.addEventListener('click', () => {
      applyStatus('loading', null);
      if (setModelStatus) setModelStatus(s.model, 'loading');
      worker.postMessage({ type: 'load', model: s.model });
    });
  }

  return {
    destroy() {
      handlers.uninstall();
      if (worker) worker.removeEventListener('message', onWorkerMessage);
    },
  };
}
