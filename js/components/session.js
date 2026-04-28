// js/components/session.js
// The current session: screenshot preview + streaming summary.
// Breakdown button + chat UI come in later tasks.

import { setMarkdown } from './markdown.js';
import { t, tFmt } from '../i18n.js';
import { getSettings, updateSession, getSession } from '../store.js';

export function mountSession(container, { worker, sessionId }) {
  const s = getSettings();
  const sess = getSession(sessionId);
  if (!sess) {
    container.textContent = 'session not found';
    return { destroy() {} };
  }

  container.innerHTML = `
    <div class="session">
      <img class="session-preview" src="${sess.image}" alt="screenshot">
      <h2>${t('session.summary', s.lang)}</h2>
      <div id="session-status" class="muted"></div>
      <div id="session-summary" class="markdown-out">${sess.summary || ''}</div>
      <div class="session-actions">
        <button id="session-cancel" style="display:none" type="button">${t('session.cancel', s.lang)}</button>
      </div>
    </div>
  `;

  const status = container.querySelector('#session-status');
  const summaryEl = container.querySelector('#session-summary');
  const cancelBtn = container.querySelector('#session-cancel');

  if (sess.summary) setMarkdown(summaryEl, sess.summary);

  let streamedText = sess.summary || '';
  let currentRequestId = null;
  let nextRequestId = Math.floor(Math.random() * 1000) + 1;

  function onWorkerMessage(e) {
    const m = e.data;
    if (currentRequestId !== null && m.requestId !== currentRequestId) return;

    if (m.type === 'loading') status.textContent = tFmt('session.loading', s.lang, { pct: m.pct });
    else if (m.type === 'ready') status.textContent = '';
    else if (m.type === 'started') {
      streamedText = '';
      summaryEl.innerHTML = '';
      status.textContent = t('session.thinking', s.lang);
      cancelBtn.style.display = '';
    }
    else if (m.type === 'token') {
      streamedText += m.text;
      setMarkdown(summaryEl, streamedText);
    }
    else if (m.type === 'done' || m.type === 'cancelled') {
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      updateSession(sessionId, { summary: streamedText });
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

  async function startSummarize() {
    if (sess.summary) return;
    const blob = await (await fetch(sess.image)).blob();
    const bitmap = await createImageBitmap(blob);
    const requestId = nextRequestId++;
    currentRequestId = requestId;
    worker.postMessage(
      { type: 'summarize', requestId, image: bitmap, lang: s.lang, model: s.model },
      [bitmap],
    );
  }

  startSummarize();

  return {
    destroy() {
      worker.removeEventListener('message', onWorkerMessage);
      if (currentRequestId !== null) {
        worker.postMessage({ type: 'cancel', requestId: currentRequestId });
      }
    },
  };
}
