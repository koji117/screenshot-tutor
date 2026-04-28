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
      <button id="session-breakdown-btn" class="primary" type="button">
        ${t('session.breakdown', s.lang)}
      </button>
      <h2 id="session-breakdown-heading" style="display:none">${t('session.breakdown', s.lang)}</h2>
      <div id="session-breakdown" class="markdown-out" style="display:none"></div>
      <h2>${t('session.chatHeading', s.lang)}</h2>
      <div id="session-chat" class="chat"></div>
      <form id="session-chat-form" class="chat-form">
        <input id="session-chat-input" type="text"
               placeholder="${t('session.askPlaceholder', s.lang)}" autocomplete="off">
        <button type="submit" class="primary">${t('session.send', s.lang)}</button>
      </form>
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
  const chatList = container.querySelector('#session-chat');
  const chatForm = container.querySelector('#session-chat-form');
  const chatInput = container.querySelector('#session-chat-input');

  if (sess.summary) setMarkdown(summaryEl, sess.summary);

  if (sess.breakdown) {
    breakdownBtn.style.display = 'none';
    breakdownHeading.style.display = '';
    breakdownEl.style.display = '';
    setMarkdown(breakdownEl, sess.breakdown);
  }

  function renderChat() {
    const current = getSession(sessionId);
    if (!current || !current.chat || current.chat.length === 0) {
      chatList.innerHTML = '';
      return;
    }
    chatList.innerHTML = current.chat.map((m) => `
      <div class="chat-msg chat-${m.role}">
        <div class="chat-role">${m.role === 'user' ? t('session.userRole', s.lang) : t('session.assistantRole', s.lang)}</div>
        <div class="chat-text"></div>
      </div>
    `).join('');
    const nodes = chatList.querySelectorAll('.chat-text');
    current.chat.forEach((m, i) => setMarkdown(nodes[i], m.text));
  }
  renderChat();

  let streamedText = sess.summary || '';
  let breakdownText = sess.breakdown || '';
  let currentRequestId = null;
  let nextRequestId = Math.floor(Math.random() * 1000) + 1;
  let activeOp = null;
  let chatStreamingEl = null;
  let chatStreamingText = '';

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
      } else if (activeOp === 'chat') {
        chatStreamingText += m.text;
        if (chatStreamingEl) setMarkdown(chatStreamingEl, chatStreamingText);
      }
    }
    else if (m.type === 'done' || m.type === 'cancelled') {
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      if (activeOp === 'summarize') updateSession(sessionId, { summary: streamedText });
      else if (activeOp === 'breakdown') updateSession(sessionId, { breakdown: breakdownText });
      else if (activeOp === 'chat') {
        const current = getSession(sessionId);
        const newChat = (current.chat || []).slice();
        newChat.push({ role: 'assistant', text: chatStreamingText, ts: Date.now() });
        updateSession(sessionId, { chat: newChat });
        chatStreamingEl = null;
        chatStreamingText = '';
      }
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

  async function startChat(userText) {
    const current = getSession(sessionId);
    if (!current) return;

    const newChat = (current.chat || []).slice();
    newChat.push({ role: 'user', text: userText, ts: Date.now() });
    updateSession(sessionId, { chat: newChat });
    renderChat();

    const bubble = document.createElement('div');
    bubble.className = 'chat-msg chat-assistant';
    bubble.innerHTML = `<div class="chat-role">${t('session.assistantRole', s.lang)}</div><div class="chat-text"></div>`;
    chatList.appendChild(bubble);
    chatStreamingEl = bubble.querySelector('.chat-text');
    chatStreamingText = '';

    const blob = await (await fetch(current.image)).blob();
    const bitmap = await createImageBitmap(blob);
    const requestId = nextRequestId++;
    currentRequestId = requestId;
    activeOp = 'chat';
    worker.postMessage(
      {
        type: 'chat',
        requestId,
        image: bitmap,
        summary: current.summary || '',
        history: newChat.slice(0, -1),
        userMessage: userText,
        lang: s.lang,
        model: s.model,
      },
      [bitmap],
    );
  }

  chatForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const text = chatInput.value.trim();
    if (!text) return;
    chatInput.value = '';
    startChat(text);
  });

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
