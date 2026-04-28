// js/components/empty-state.js
// Initial paste/drop/pick zone. Visible when no session is active.

import { installInputHandlers, captureScreen } from '../input.js';
import { t } from '../i18n.js';
import { getSettings } from '../store.js';

export function mountEmptyState(container, { onImage, onError }) {
  const s = getSettings();
  const supportsWebGPU = 'gpu' in navigator;

  container.innerHTML = `
    <div class="empty" id="empty-zone" tabindex="0">
      <h2>${t('empty.heading', s.lang)}</h2>
      <p class="muted">${t('empty.hint', s.lang)}</p>
      <div class="empty-actions">
        <button id="empty-pick" type="button">${t('empty.pick', s.lang)}</button>
        <button id="empty-capture" type="button">📸 ${t('empty.capture', s.lang)}</button>
      </div>
      ${!supportsWebGPU
        ? `<p class="error" style="margin-top:1rem">${t('empty.webgpuRequired', s.lang)}</p>`
        : ''}
      <div id="empty-msg" class="muted" style="margin-top:1rem"></div>
    </div>
  `;

  const zone = container.querySelector('#empty-zone');
  const msg = container.querySelector('#empty-msg');

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

  return {
    destroy() { handlers.uninstall(); },
  };
}
