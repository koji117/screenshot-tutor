// js/components/synthesis.js
// Cross-session synthesis view. Reads all past summaries (newest first)
// and asks the worker to produce a "what you've been studying" recap.
// When the synthesis finishes, the source sessions are archived (removed
// from in-app history) — they can be preserved beforehand by exporting
// individual sessions to Obsidian, or by exporting the synthesis itself.

import { setMarkdown } from './markdown.js';
import { t, tFmt } from '../i18n.js';
import { getSettings, getSessions, deleteSession } from '../store.js';
import { exportSynthesis, isFileSystemAccessSupported } from '../exports.js';

export function mountSynthesis(container, { worker, onAfterClear }) {
  const s = getSettings();
  const sessions = getSessions();
  const usable = sessions.filter((sess) => sess.summary && sess.summary.trim().length > 0);
  const summaries = usable.map((sess) => sess.summary);
  const usedIds = usable.map((sess) => sess.id);
  const sessionCount = summaries.length;

  container.innerHTML = `
    <div class="synthesis">
      <h2 class="synthesis-heading">${t('synthesis.heading', s.lang)}</h2>
      <p class="synthesis-sub muted">${tFmt('synthesis.subheading', s.lang, { count: sessionCount })}</p>
      <div id="synthesis-status" class="muted"></div>
      <div id="synthesis-out" class="markdown-out"></div>
      <div class="session-actions">
        <button id="synthesis-cancel" style="display:none" type="button">${t('session.cancel', s.lang)}</button>
        <button id="synthesis-export" type="button" disabled>
          ${t('synthesis.export', s.lang)}
        </button>
      </div>
    </div>
  `;

  const status = container.querySelector('#synthesis-status');
  const outEl = container.querySelector('#synthesis-out');
  const cancelBtn = container.querySelector('#synthesis-cancel');
  const exportBtn = container.querySelector('#synthesis-export');

  if (sessionCount < 2) {
    status.textContent = t('synthesis.notEnough', s.lang);
    return { destroy() {} };
  }

  let streamedText = '';
  let currentRequestId = null;
  let archivedYet = false;
  const requestId = Math.floor(Math.random() * 1_000_000) + 1;

  // requestAnimationFrame-coalesced rendering (see session.js for the
  // rationale — setMarkdown is O(N) per call, doing it per token is O(N²)).
  let rafHandle = null;
  function scheduleRender() {
    if (rafHandle != null) return;
    rafHandle = requestAnimationFrame(() => {
      rafHandle = null;
      setMarkdown(outEl, streamedText);
    });
  }
  function flushRender() {
    if (rafHandle != null) {
      cancelAnimationFrame(rafHandle);
      rafHandle = null;
    }
    setMarkdown(outEl, streamedText);
  }

  function archiveSources() {
    if (archivedYet) return;
    archivedYet = true;
    for (const id of usedIds) deleteSession(id);
    if (onAfterClear) onAfterClear();
    if (window.__showToast) {
      window.__showToast(tFmt('synthesis.archived', s.lang, { count: usedIds.length }));
    }
  }

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
      scheduleRender();
    }
    else if (m.type === 'done') {
      flushRender();
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      if (isFileSystemAccessSupported()) exportBtn.disabled = false;
      archiveSources();
    }
    else if (m.type === 'cancelled') {
      flushRender();
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      // Cancelled mid-generation: don't archive — the synthesis is incomplete.
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

  exportBtn.addEventListener('click', async () => {
    if (!isFileSystemAccessSupported()) {
      window.__showToast && window.__showToast(t('session.exportNotSupported', s.lang), 'error');
      return;
    }
    exportBtn.disabled = true;
    try {
      const { filename } = await exportSynthesis(streamedText, sessionCount);
      window.__showToast && window.__showToast(
        tFmt('session.exportSuccess', s.lang, { filename })
      );
    } catch (err) {
      const aborted = err && (err.name === 'AbortError' || /aborted|denied/i.test(err.message || ''));
      const msg = aborted
        ? t('session.exportCancelled', s.lang)
        : tFmt('session.exportFailed', s.lang, { error: err && err.message || String(err) });
      window.__showToast && window.__showToast(msg, aborted ? undefined : 'error');
    } finally {
      exportBtn.disabled = false;
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
      if (rafHandle != null) {
        cancelAnimationFrame(rafHandle);
        rafHandle = null;
      }
      if (currentRequestId !== null) {
        worker.postMessage({ type: 'cancel', requestId: currentRequestId });
      }
    },
  };
}
