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
      <button id="session-breakdown-btn" class="primary" type="button" style="margin-top:1rem">
        ${t('session.breakdown', s.lang)}
      </button>
      <h2 id="session-breakdown-heading" style="display:none">${t('session.breakdown', s.lang)}</h2>
      <div id="session-breakdown" class="markdown-out" style="display:none"></div>
      <div class="session-actions">
        <button id="session-cancel" style="display:none" type="button">${t('session.cancel', s.lang)}</button>
      </div>
    </div>
  `;

  const status = container.querySelector('#session-status');
  const summaryEl = container.querySelector('#session-summary');
  const cancelBtn = container.querySelector('#session-cancel');
  const breakdownBtn = container.querySelector('#session-breakdown-btn');
  const breakdownHeading = container.querySelector('#session-breakdown-heading');
  const breakdownEl = container.querySelector('#session-breakdown');

  if (sess.summary) setMarkdown(summaryEl, sess.summary);

  if (sess.breakdown) {
    breakdownBtn.style.display = 'none';
    breakdownHeading.style.display = '';
    breakdownEl.style.display = '';
    setMarkdown(breakdownEl, sess.breakdown);
  }

  let streamedText = sess.summary || '';
  let breakdownText = sess.breakdown || '';
  let currentRequestId = null;
  let nextRequestId = Math.floor(Math.random() * 1000) + 1;
  let activeOp = null;

  function onWorkerMessage(e) {
    const m = e.data;
    if (currentRequestId !== null && m.requestId !== currentRequestId) return;

    if (m.type === 'loading') status.textContent = tFmt('session.loading', s.lang, { pct: m.pct });
    else if (m.type === 'ready') status.textContent = '';
    else if (m.type === 'started') {
      if (activeOp === 'summarize') {
        streamedText = '';
        summaryEl.innerHTML = '';
      } else if (activeOp === 'breakdown') {
        breakdownText = '';
        breakdownEl.innerHTML = '';
      }
      status.textContent = t('session.thinking', s.lang);
      cancelBtn.style.display = '';
    }
    else if (m.type === 'token') {
      if (activeOp === 'summarize') {
        streamedText += m.text;
        setMarkdown(summaryEl, streamedText);
      } else if (activeOp === 'breakdown') {
        breakdownText += m.text;
        setMarkdown(breakdownEl, breakdownText);
      }
    }
    else if (m.type === 'done' || m.type === 'cancelled') {
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      if (activeOp === 'summarize') updateSession(sessionId, { summary: streamedText });
      else if (activeOp === 'breakdown') updateSession(sessionId, { breakdown: breakdownText });
      activeOp = null;
    }
    else if (m.type === 'error') {
      status.textContent = tFmt('session.errorWorker', s.lang, { error: m.error });
      status.classList.add('error');
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      activeOp = null;
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
    activeOp = 'summarize';
    worker.postMessage(
      { type: 'summarize', requestId, image: bitmap, lang: s.lang, model: s.model },
      [bitmap],
    );
  }

  async function startBreakdown() {
    const current = getSession(sessionId);
    if (!current) return;
    breakdownBtn.style.display = 'none';
    breakdownHeading.style.display = '';
    breakdownEl.style.display = '';
    breakdownEl.innerHTML = '';
    breakdownText = '';
    const blob = await (await fetch(current.image)).blob();
    const bitmap = await createImageBitmap(blob);
    const requestId = nextRequestId++;
    currentRequestId = requestId;
    activeOp = 'breakdown';
    worker.postMessage(
      {
        type: 'breakdown',
        requestId,
        image: bitmap,
        summary: current.summary || '',
        lang: s.lang,
        model: s.model,
      },
      [bitmap],
    );
  }

  breakdownBtn.addEventListener('click', startBreakdown);

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
