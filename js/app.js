// js/app.js
// Vertical slice: paste → normalize → worker.summarize → streamed display.
import { installInputHandlers } from './input.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div class="sandbox" id="zone" tabindex="0">
    <h1>Screenshot Tutor</h1>
    <p>Paste (Cmd+V), drop, or <button id="pick">pick a file</button>.
       Model: <select id="model"><option value="e2b">e2b (1.5GB)</option><option value="e4b" selected>e4b (3GB)</option></select>
       Lang: <select id="lang"><option value="en" selected>EN</option><option value="ja">JA</option></select>
       <button id="cancel" style="display:none">Cancel</button>
    </p>
    <div id="preview"></div>
    <div id="status" class="muted"></div>
    <pre id="output"></pre>
    <div id="msg" class="muted"></div>
  </div>
`;

const zone = document.getElementById('zone');
const preview = document.getElementById('preview');
const status = document.getElementById('status');
const output = document.getElementById('output');
const msg = document.getElementById('msg');
const modelSel = document.getElementById('model');
const langSel = document.getElementById('lang');
const cancelBtn = document.getElementById('cancel');

if (!('gpu' in navigator)) {
  msg.textContent = 'WebGPU is required. Use Chrome, Edge, or Arc on Apple Silicon.';
  msg.style.color = 'var(--error)';
}

const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
let nextRequestId = 1;
let currentRequestId = null;
let currentImageDataUrl = null;

worker.onmessage = (e) => {
  const m = e.data;
  if (m.type === 'loading') status.textContent = `loading model… ${m.pct}%`;
  else if (m.type === 'ready') status.textContent = 'model ready';
  else if (m.type === 'started') { output.textContent = ''; status.textContent = 'generating…'; }
  else if (m.type === 'token') output.textContent += m.text;
  else if (m.type === 'done') { status.textContent = 'done'; cancelBtn.style.display = 'none'; currentRequestId = null; }
  else if (m.type === 'cancelled') { status.textContent = 'cancelled'; cancelBtn.style.display = 'none'; currentRequestId = null; }
  else if (m.type === 'error') {
    status.textContent = 'error: ' + m.error;
    status.style.color = 'var(--error)';
    cancelBtn.style.display = 'none';
    currentRequestId = null;
  } else if (m.type === 'warn') {
    console.warn('[worker]', m.message);
  }
};

worker.onerror = (e) => {
  status.textContent = 'worker error: ' + (e.message || 'unknown');
  status.style.color = 'var(--error)';
};

async function runSummarize(imageDataUrl) {
  const blob = await (await fetch(imageDataUrl)).blob();
  const bitmap = await createImageBitmap(blob);
  const requestId = nextRequestId++;
  currentRequestId = requestId;
  cancelBtn.style.display = '';
  worker.postMessage(
    {
      type: 'summarize',
      requestId,
      image: bitmap,
      lang: langSel.value,
      model: modelSel.value,
    },
    [bitmap],
  );
}

const handlers = installInputHandlers(
  zone,
  async ({ image, width, height }) => {
    msg.textContent = '';
    currentImageDataUrl = image;
    preview.innerHTML = `<img src="${image}" style="max-width:100%; border:1px solid #ccc;">`;
    status.textContent = `loaded ${width}x${height}`;
    output.textContent = '';
    await runSummarize(image);
  },
  (err) => {
    msg.textContent = 'error: ' + err;
  },
);

document.getElementById('pick').addEventListener('click', () => handlers.pickFile());

cancelBtn.addEventListener('click', () => {
  if (currentRequestId !== null) {
    worker.postMessage({ type: 'cancel', requestId: currentRequestId });
  }
});
