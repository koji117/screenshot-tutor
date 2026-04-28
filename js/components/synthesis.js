// js/components/synthesis.js
// Cross-session synthesis view. Reads all past summaries (newest first)
// and asks the worker to produce a "what you've been studying" recap.

import { setMarkdown } from './markdown.js';
import { t, tFmt } from '../i18n.js';
import { getSettings, getSessions } from '../store.js';

export function mountSynthesis(container, { worker }) {
  const s = getSettings();
  const sessions = getSessions();
  const summaries = sessions
    .map((sess) => sess.summary)
    .filter((sum) => sum && sum.trim().length > 0);

  container.innerHTML = `
    <div class="synthesis">
      <h2 class="synthesis-heading">${t('synthesis.heading', s.lang)}</h2>
      <p class="synthesis-sub muted">${tFmt('synthesis.subheading', s.lang, { count: summaries.length })}</p>
      <div id="synthesis-status" class="muted"></div>
      <div id="synthesis-out" class="markdown-out"></div>
      <div class="session-actions">
        <button id="synthesis-cancel" style="display:none" type="button">${t('session.cancel', s.lang)}</button>
      </div>
    </div>
  `;

  const status = container.querySelector('#synthesis-status');
  const outEl = container.querySelector('#synthesis-out');
  const cancelBtn = container.querySelector('#synthesis-cancel');

  if (summaries.length < 2) {
    status.textContent = t('synthesis.notEnough', s.lang);
    return { destroy() {} };
  }

  let streamedText = '';
  let currentRequestId = null;
  const requestId = Math.floor(Math.random() * 1_000_000) + 1;

  function onWorkerMessage(e) {
    const m = e.data;

    if (m.type === 'loading') {
      if (currentRequestId !== null) {
        status.textContent = tFmt('session.loading', s.lang, { pct: m.pct });
      }
      return;
    }

    if (m.requestId == null || m.requestId !== currentRequestId) return;

    if (m.type === 'started') {
      streamedText = '';
      outEl.innerHTML = '';
      status.textContent = t('synthesis.thinking', s.lang);
      cancelBtn.style.display = '';
    }
    else if (m.type === 'token') {
      streamedText += m.text;
      setMarkdown(outEl, streamedText);
    }
    else if (m.type === 'done' || m.type === 'cancelled') {
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
    }
    else if (m.type === 'error') {
      status.textContent = tFmt('session.errorWorker', s.lang, { error: m.error });
      status.classList.add('error');
      cancelBtn.style.display = 'none';
      currentRequestId = null;
    }
  }

  worker.addEventListener('message', onWorkerMessage);

  cancelBtn.addEventListener('click', () => {
    if (currentRequestId !== null) {
      worker.postMessage({ type: 'cancel', requestId: currentRequestId });
    }
  });

  // Start the synthesis. Newest first matches the order summaries are
  // stored in.
  currentRequestId = requestId;
  worker.postMessage({
    type: 'synthesize',
    requestId,
    summaries,
    lang: s.lang,
    model: s.model,
  });

  return {
    destroy() {
      worker.removeEventListener('message', onWorkerMessage);
      if (currentRequestId !== null) {
        worker.postMessage({ type: 'cancel', requestId: currentRequestId });
      }
    },
  };
}
