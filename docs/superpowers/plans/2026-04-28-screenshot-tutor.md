# Screenshot Tutor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A browser-only study tutor that takes a pasted/dropped screenshot and produces a streamed summary, with optional structured breakdown and chat follow-ups, in English or Japanese.

**Architecture:** Static site (no build) with a single Web Worker hosting Gemma 4 multimodal via Transformers.js 4.2.0 on WebGPU. Plain ES modules; `localStorage` for settings + capped session history; image input normalized to JPEG data URLs and transferred to the worker as `ImageBitmap`.

**Tech Stack:** Vanilla HTML/CSS/JS, ES modules, Web Workers, WebGPU, `@huggingface/transformers@4.2.0`, `localStorage`. No npm, no bundler, no framework.

**Spec:** `docs/superpowers/specs/2026-04-28-screenshot-tutor-design.md`

---

## Task 1: Project Scaffolding

**Files:**
- Create: `index.html`
- Create: `css/app.css`
- Create: `js/app.js`
- Create: `manifest.json`
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```
.DS_Store
node_modules/
*.log
.idea/
.vscode/
```

- [ ] **Step 2: Create `manifest.json`**

```json
{
  "name": "Screenshot Tutor",
  "short_name": "Tutor",
  "start_url": "/",
  "display": "standalone",
  "theme_color": "#1a1a1a",
  "background_color": "#ffffff",
  "icons": []
}
```

- [ ] **Step 3: Create `index.html`**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Screenshot Tutor</title>
  <link rel="manifest" href="/manifest.json">
  <link rel="stylesheet" href="/css/app.css">
</head>
<body>
  <div id="app"></div>
  <script type="module" src="/js/app.js"></script>
</body>
</html>
```

- [ ] **Step 4: Create `css/app.css`**

```css
:root {
  --bg: #ffffff;
  --fg: #1a1a1a;
  --muted: #666;
  --border: #e5e5e5;
  --accent: #2563eb;
  --accent-bg: #eff6ff;
  --error: #dc2626;
  --max-width: 760px;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  padding: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
  background: var(--bg);
  color: var(--fg);
  font-size: 16px;
  line-height: 1.5;
}

#app {
  min-height: 100vh;
}
```

- [ ] **Step 5: Create `js/app.js`**

```js
// Bootstrap. Real wiring lands in later tasks.
const root = document.getElementById('app');
root.textContent = 'Screenshot Tutor — scaffolding ready.';
```

- [ ] **Step 6: Create `README.md`**

```markdown
# Screenshot Tutor

A local-LLM browser app that takes a screenshot and produces a study-friendly summary, with optional structured breakdown and chat follow-ups. Runs Gemma 4 multimodal via Transformers.js on WebGPU — no API keys, no server.

## Run

```
python3 -m http.server 8000
# open http://localhost:8000
```

Requires Chrome, Edge, or Arc with WebGPU. First model load downloads ~1.5GB (e2b) or ~3GB (e4b) and takes a few minutes.

## Design

See `docs/superpowers/specs/2026-04-28-screenshot-tutor-design.md`.
```

- [ ] **Step 7: Verify the static site serves**

Run: `python3 -m http.server 8000 &` then `curl -s http://localhost:8000/ | head -3`
Expected: HTML response starting with `<!doctype html>`. Then kill the server.

- [ ] **Step 8: Commit**

```bash
git add .gitignore manifest.json index.html css/app.css js/app.js README.md
git commit -m "feat: project scaffolding"
```

---

## Task 2: Image Normalization (TDD)

**Files:**
- Create: `js/input.js`
- Test: `js/input.test.html`

`normalizeImage(blob)` takes a Blob (image), downscales to max 1280px on the longest edge, encodes as JPEG q=0.85, and also produces a 240px thumbnail. Returns `{image, thumb, width, height}` where `image` and `thumb` are JPEG data URLs.

- [ ] **Step 1: Write the failing test**

Create `js/input.test.html`:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>input.js unit tests</title>
  <style>
    body { font-family: monospace; padding: 2em; max-width: 900px; }
    .pass { color: green; }
    .fail { color: red; font-weight: bold; }
    pre { background: #f4f4f4; padding: 0.5em; }
  </style>
</head>
<body>
  <h1>input.js — unit tests</h1>
  <div id="out"></div>
  <script type="module">
    import { normalizeImage } from './input.js';

    const out = document.getElementById('out');
    let passed = 0, failed = 0;

    function log(name, ok, detail) {
      const line = document.createElement('div');
      line.className = ok ? 'pass' : 'fail';
      line.textContent = (ok ? '✓ ' : '✗ ') + name;
      out.appendChild(line);
      if (!ok && detail) {
        const pre = document.createElement('pre');
        pre.textContent = detail;
        out.appendChild(pre);
        failed++;
      } else if (ok) passed++;
    }

    // Build a synthetic image blob of given dimensions.
    async function makeBlob(w, h, color = '#abc') {
      const canvas = new OffscreenCanvas(w, h);
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = color;
      ctx.fillRect(0, 0, w, h);
      return await canvas.convertToBlob({ type: 'image/png' });
    }

    async function dimsOfDataUrl(dataUrl) {
      const img = new Image();
      img.src = dataUrl;
      await img.decode();
      return { w: img.naturalWidth, h: img.naturalHeight };
    }

    // Test 1: small image stays small (no upscaling)
    {
      const blob = await makeBlob(800, 600);
      const r = await normalizeImage(blob);
      const d = await dimsOfDataUrl(r.image);
      log('800x600 stays 800x600', d.w === 800 && d.h === 600,
        'got ' + d.w + 'x' + d.h);
      log('output is JPEG data URL', r.image.startsWith('data:image/jpeg;base64,'));
    }

    // Test 2: oversized image downscales to 1280 max edge, preserving aspect
    {
      const blob = await makeBlob(2560, 1440);
      const r = await normalizeImage(blob);
      const d = await dimsOfDataUrl(r.image);
      log('2560x1440 downscales to 1280x720',
        d.w === 1280 && d.h === 720,
        'got ' + d.w + 'x' + d.h);
    }

    // Test 3: tall image: height becomes 1280
    {
      const blob = await makeBlob(800, 3200);
      const r = await normalizeImage(blob);
      const d = await dimsOfDataUrl(r.image);
      log('800x3200 downscales to 320x1280',
        d.w === 320 && d.h === 1280,
        'got ' + d.w + 'x' + d.h);
    }

    // Test 4: thumbnail is 240 max edge
    {
      const blob = await makeBlob(2000, 1000);
      const r = await normalizeImage(blob);
      const d = await dimsOfDataUrl(r.thumb);
      log('thumb downscales to 240x120',
        d.w === 240 && d.h === 120,
        'got ' + d.w + 'x' + d.h);
    }

    // Test 5: returns reported dimensions
    {
      const blob = await makeBlob(2560, 1440);
      const r = await normalizeImage(blob);
      log('reports normalized width=1280', r.width === 1280, 'got ' + r.width);
      log('reports normalized height=720', r.height === 720, 'got ' + r.height);
    }

    const summary = document.createElement('h2');
    summary.textContent = `${passed} passed, ${failed} failed`;
    summary.style.color = failed ? 'red' : 'green';
    out.appendChild(summary);
  </script>
</body>
</html>
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/js/input.test.html` in Chrome.
Expected: failures because `input.js` doesn't exist.

- [ ] **Step 3: Implement `js/input.js`**

```js
// js/input.js
// Image normalization and input handlers (paste / drop / file pick).

const MAX_EDGE = 1280;
const THUMB_EDGE = 240;
const JPEG_QUALITY = 0.85;

// Compute target dimensions that preserve aspect ratio and fit within maxEdge.
// Never upscales.
function fit(w, h, maxEdge) {
  if (w <= maxEdge && h <= maxEdge) return { w, h };
  const scale = w >= h ? maxEdge / w : maxEdge / h;
  return { w: Math.round(w * scale), h: Math.round(h * scale) };
}

async function blobToBitmap(blob) {
  return await createImageBitmap(blob);
}

function bitmapToJpegDataUrl(bitmap, w, h, quality) {
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  ctx.drawImage(bitmap, 0, 0, w, h);
  return canvas.toDataURL('image/jpeg', quality);
}

export async function normalizeImage(blob) {
  const bitmap = await blobToBitmap(blob);
  try {
    const main = fit(bitmap.width, bitmap.height, MAX_EDGE);
    const thumb = fit(bitmap.width, bitmap.height, THUMB_EDGE);
    const image = bitmapToJpegDataUrl(bitmap, main.w, main.h, JPEG_QUALITY);
    const thumbUrl = bitmapToJpegDataUrl(bitmap, thumb.w, thumb.h, JPEG_QUALITY);
    return { image, thumb: thumbUrl, width: main.w, height: main.h };
  } finally {
    bitmap.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Reload `http://localhost:8000/js/input.test.html`.
Expected: all 7 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add js/input.js js/input.test.html
git commit -m "feat: image normalization with downscale + thumbnail"
```

---

## Task 3: Input Handlers (Manual Test)

**Files:**
- Modify: `js/input.js` — add `installInputHandlers(container, onImage)`
- Modify: `js/app.js` — wire a sandbox UI that previews pasted/dropped images

`installInputHandlers` listens for paste/drop/file-pick on a container element and calls `onImage(normalizedResult)` when an image arrives. Returns an `uninstall` function for cleanup.

- [ ] **Step 1: Append handler logic to `js/input.js`**

Add at the bottom of `js/input.js`:

```js
// Returns the first image File from a clipboard or drag DataTransfer.
function firstImageFromTransfer(dt) {
  if (!dt) return null;
  const items = dt.items ? Array.from(dt.items) : [];
  for (const it of items) {
    if (it.kind === 'file' && it.type && it.type.startsWith('image/')) {
      const f = it.getAsFile();
      if (f) return f;
    }
  }
  const files = dt.files ? Array.from(dt.files) : [];
  for (const f of files) {
    if (f.type && f.type.startsWith('image/')) return f;
  }
  return null;
}

// Wire paste/drop/file-pick on `container`. `onImage` is called with the
// normalizeImage() result. `onError` is called with a string when a paste
// or drop happened but contained no image.
export function installInputHandlers(container, onImage, onError) {
  async function handleBlob(blob) {
    try {
      const result = await normalizeImage(blob);
      onImage(result);
    } catch (err) {
      if (onError) onError('failed to read image: ' + (err.message || err));
    }
  }

  function onPaste(e) {
    const blob = firstImageFromTransfer(e.clipboardData);
    if (!blob) {
      if (onError) onError("clipboard didn't contain an image");
      return;
    }
    e.preventDefault();
    handleBlob(blob);
  }

  function onDragOver(e) {
    e.preventDefault();
    container.classList.add('drag-over');
  }

  function onDragLeave() {
    container.classList.remove('drag-over');
  }

  function onDrop(e) {
    e.preventDefault();
    container.classList.remove('drag-over');
    const blob = firstImageFromTransfer(e.dataTransfer);
    if (!blob) {
      if (onError) onError("dropped item wasn't an image");
      return;
    }
    handleBlob(blob);
  }

  function pickFile() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.addEventListener('change', () => {
      const f = input.files && input.files[0];
      if (f) handleBlob(f);
    });
    input.click();
  }

  document.addEventListener('paste', onPaste);
  container.addEventListener('dragover', onDragOver);
  container.addEventListener('dragleave', onDragLeave);
  container.addEventListener('drop', onDrop);

  return {
    pickFile,
    uninstall() {
      document.removeEventListener('paste', onPaste);
      container.removeEventListener('dragover', onDragOver);
      container.removeEventListener('dragleave', onDragLeave);
      container.removeEventListener('drop', onDrop);
    },
  };
}
```

- [ ] **Step 2: Replace `js/app.js` with a sandbox UI**

```js
// js/app.js
// Sandbox UI: paste / drop / pick zone that previews the normalized image.
// Replaced in later tasks with the real component-based UI.
import { installInputHandlers } from './input.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div class="sandbox" id="zone" tabindex="0">
    <h1>Screenshot Tutor — sandbox</h1>
    <p>Paste (Cmd+V), drop, or <button id="pick">pick a file</button>.</p>
    <div id="preview"></div>
    <div id="msg" class="muted"></div>
  </div>
`;

const zone = document.getElementById('zone');
const preview = document.getElementById('preview');
const msg = document.getElementById('msg');

const handlers = installInputHandlers(
  zone,
  ({ image, thumb, width, height }) => {
    msg.textContent = `loaded ${width}x${height}`;
    preview.innerHTML = `<img src="${image}" style="max-width:100%; border:1px solid #ccc;">`;
  },
  (err) => {
    msg.textContent = 'error: ' + err;
  },
);

document.getElementById('pick').addEventListener('click', () => handlers.pickFile());
```

- [ ] **Step 3: Append sandbox styles to `css/app.css`**

```css
.sandbox {
  max-width: var(--max-width);
  margin: 0 auto;
  padding: 2rem;
}

.sandbox.drag-over {
  outline: 2px dashed var(--accent);
  outline-offset: -8px;
}

.muted { color: var(--muted); margin-top: 0.5rem; }
```

- [ ] **Step 4: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.

Verify all three input methods:
- Take a screenshot (`Cmd+Shift+4`, hold Ctrl to copy to clipboard) and `Cmd+V` into the page → image preview appears with dimensions
- Drag an image from Finder onto the page → preview appears
- Click "pick a file" → file picker opens; select an image → preview appears

Verify error path: `Cmd+V` on plain text → "clipboard didn't contain an image" appears.

- [ ] **Step 5: Commit**

```bash
git add js/input.js js/app.js css/app.css
git commit -m "feat: paste/drop/file-pick handlers with sandbox UI"
```

---

## Task 4: Vertical Slice — Worker + Summarize End-to-End

**Files:**
- Create: `js/worker.js`
- Modify: `js/app.js` — extend sandbox to call worker and stream tokens

This is the highest-risk task: it proves Gemma 4 multimodal works in Transformers.js 4.2.0 from a Web Worker. Goal is end-to-end paste → worker → streamed summary.

**Note on multimodal API:** Two paths are possible — `processor.apply_chat_template()` (canonical) or manual prompt assembly with image tokens. The reference app's text-only chat-worker.js had a `trim` filter bug with `apply_chat_template`. We try the canonical path first and fall back to manual assembly only if it throws. The fallback shape is documented in the implementation below.

- [ ] **Step 1: Create `js/worker.js`**

```js
// js/worker.js
// Web Worker that hosts Gemma 4 multimodal via Transformers.js.
//
// Verified Transformers.js version: 4.2.0
// Verified MODEL_REPOS: onnx-community/gemma-4-E2B-it-ONNX,
//   onnx-community/gemma-4-E4B-it-ONNX
//
// Multimodal note: Gemma 4 is "any-to-any". The processor accepts both
// images and text. We use processor.apply_chat_template() with the
// multimodal content format. If that throws (Jinja template issues like
// the one the reference app hit), the catch path falls back to manual
// prompt assembly using <start_of_turn> markers and the image token.

import {
  AutoProcessor,
  Gemma4ForConditionalGeneration,
  TextStreamer,
  InterruptableStoppingCriteria,
  env,
} from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.2.0';

env.allowLocalModels = false;
env.useBrowserCache = true;

const MODEL_REPOS = {
  e2b: 'onnx-community/gemma-4-E2B-it-ONNX',
  e4b: 'onnx-community/gemma-4-E4B-it-ONNX',
};

let processor = null;
let model = null;
let currentModel = null;
let cancelRequested = false;
let stoppingCriteria = null;
let inFlight = false;

async function loadModel(which) {
  if (model && processor && currentModel === which) return;
  const repoId = MODEL_REPOS[which];
  if (!repoId) throw new Error('unknown model: ' + which);

  const progressCallback = (info) => {
    try {
      if (!info) return;
      let pct = null;
      if (typeof info.progress === 'number') pct = info.progress;
      else if (info.status === 'progress' && typeof info.loaded === 'number'
                && typeof info.total === 'number' && info.total > 0) {
        pct = (info.loaded / info.total) * 100;
      }
      if (pct !== null) self.postMessage({ type: 'loading', pct: Math.round(pct) });
    } catch {}
  };

  processor = await AutoProcessor.from_pretrained(repoId, {
    progress_callback: progressCallback,
  });
  model = await Gemma4ForConditionalGeneration.from_pretrained(repoId, {
    dtype: 'q4f16',
    device: 'webgpu',
    progress_callback: progressCallback,
  });
  currentModel = which;
}

// Build inputs for a single-turn user message containing image + text.
// Tries apply_chat_template first, falls back to manual prompt assembly.
async function buildInputs(image, text) {
  const messages = [
    {
      role: 'user',
      content: [
        { type: 'image', image },
        { type: 'text', text },
      ],
    },
  ];

  try {
    return await processor.apply_chat_template(messages, {
      add_generation_prompt: true,
      tokenize: true,
      return_dict: true,
      return_tensors: 'pt',
    });
  } catch (err) {
    // Fallback: manual prompt assembly. Gemma 4 uses <image_soft_token>
    // as the placeholder for image embeddings. The processor still needs
    // to be called with both image and text to compute image features.
    self.postMessage({
      type: 'warn',
      message: 'apply_chat_template failed, using manual fallback: ' + (err && err.message),
    });
    const prompt =
      '<bos><start_of_turn>user\n<image_soft_token>\n' + text.trim() +
      '<end_of_turn>\n<start_of_turn>model\n';
    return await processor(prompt, image, null, { add_special_tokens: false });
  }
}

// Stream generation with end-of-turn buffering. The streamer may deliver a
// marker like "<end_of_turn>" in pieces, so we keep up to MAX_MARKER_LEN
// chars unflushed in case it's the start of a marker.
function makeStreamer(requestId, eosTokenId) {
  const MARKERS = ['<end_of_turn>', '<start_of_turn>'];
  const MAX_MARKER_LEN = Math.max(...MARKERS.map((m) => m.length));
  let pending = '';
  let turnStopped = false;

  return {
    streamer: new TextStreamer(processor.tokenizer, {
      skip_prompt: true,
      skip_special_tokens: true,
      callback_function: (text) => {
        if (cancelRequested || turnStopped) return;
        pending += text;
        let cutAt = -1;
        for (const m of MARKERS) {
          const i = pending.indexOf(m);
          if (i >= 0 && (cutAt < 0 || i < cutAt)) cutAt = i;
        }
        if (cutAt >= 0) {
          const before = pending.slice(0, cutAt);
          if (before) self.postMessage({ type: 'token', requestId, text: before });
          pending = '';
          turnStopped = true;
          if (stoppingCriteria) {
            try { stoppingCriteria.interrupt(); } catch {}
          }
          return;
        }
        let keepFromEnd = 0;
        for (let len = Math.min(MAX_MARKER_LEN, pending.length); len >= 1; len--) {
          const tail = pending.slice(pending.length - len);
          if (MARKERS.some((m) => m.startsWith(tail))) {
            keepFromEnd = len;
            break;
          }
        }
        const safeLen = pending.length - keepFromEnd;
        if (safeLen > 0) {
          const out = pending.slice(0, safeLen);
          pending = pending.slice(safeLen);
          self.postMessage({ type: 'token', requestId, text: out });
        }
      },
    }),
    flush() {
      if (!turnStopped && pending && !cancelRequested) {
        self.postMessage({ type: 'token', requestId, text: pending });
        pending = '';
      }
    },
  };
}

self.onmessage = async (e) => {
  const msg = e.data || {};
  try {
    if (msg.type === 'load') {
      await loadModel(msg.model || 'e2b');
      self.postMessage({ type: 'ready' });
      return;
    }

    if (msg.type === 'summarize') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, image, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which || 'e2b');
        self.postMessage({ type: 'started', requestId });

        // Hardcoded summary prompt for the vertical slice. Replaced in a
        // later task by prompts.js with EN/JA variants.
        const promptText = (lang === 'ja')
          ? 'このスクリーンショットを学習者向けに要約してください。最初に太字で1文のTL;DR、その後に3〜5個の重要なポイントを箇条書きで。200語以内。'
          : 'You are a study tutor. Summarize this screenshot in markdown. First a one-sentence TL;DR (bold), then 3-5 key bullet points. Under 200 words.';

        const inputs = await buildInputs(image, promptText);

        let eosTokenId;
        try {
          const ids = processor.tokenizer.encode('<end_of_turn>', { add_special_tokens: false });
          if (Array.isArray(ids) && ids.length > 0) eosTokenId = ids[0];
        } catch {}

        const { streamer, flush } = makeStreamer(requestId, eosTokenId);

        await model.generate({
          ...inputs,
          max_new_tokens: 512,
          do_sample: false,
          streamer,
          stopping_criteria: stoppingCriteria,
          ...(eosTokenId ? { eos_token_id: eosTokenId } : {}),
        });

        flush();

        if (cancelRequested) {
          self.postMessage({ type: 'cancelled', requestId });
        } else {
          self.postMessage({ type: 'done', requestId });
        }
      } finally {
        stoppingCriteria = null;
        inFlight = false;
      }
      return;
    }

    if (msg.type === 'cancel') {
      cancelRequested = true;
      if (stoppingCriteria) {
        try { stoppingCriteria.interrupt(); } catch {}
      }
      return;
    }

    if (msg.type === 'unload') {
      if (model && typeof model.dispose === 'function') {
        try { await model.dispose(); } catch {}
      }
      model = null;
      processor = null;
      currentModel = null;
      self.postMessage({ type: 'unloaded' });
      return;
    }

    self.postMessage({ type: 'error', error: 'unknown message type: ' + msg.type });
  } catch (err) {
    console.error('[worker] error:', err);
    self.postMessage({
      type: 'error',
      error: (err && err.message) || String(err),
      requestId: msg.requestId,
    });
  }
};
```

- [ ] **Step 2: Extend `js/app.js` to call the worker**

```js
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
```

- [ ] **Step 3: Append `pre#output` styles to `css/app.css`**

```css
#output {
  white-space: pre-wrap;
  word-wrap: break-word;
  background: #f4f4f4;
  padding: 1rem;
  border-radius: 4px;
  margin-top: 1rem;
  font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  font-size: 14px;
  min-height: 4rem;
}

select { font-size: 14px; padding: 2px 6px; }
```

- [ ] **Step 4: Manual end-to-end verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/` in Chrome (or Edge/Arc).

Expected first run:
1. Paste a screenshot (a textbook page or slide is best).
2. Status shows "loading model… X%" — first load takes a few minutes.
3. Once loaded, status shows "generating…" and tokens stream into `#output`.
4. Final status: "done". Output is a markdown-ish summary.

If the canonical multimodal path failed, you'll see a `[worker] apply_chat_template failed…` warning in the console — verify the fallback path produced output anyway.

If both paths fail:
- Open DevTools console; copy the full error stack.
- Check that the model card at `https://huggingface.co/onnx-community/gemma-4-E4B-it-ONNX` documents the canonical multimodal call shape.
- Adjust `buildInputs` in `js/worker.js` based on the model card's example.

- [ ] **Step 5: Commit**

```bash
git add js/worker.js js/app.js css/app.css
git commit -m "feat: vertical slice — Gemma 4 multimodal worker + summarize end-to-end"
```

---

## Task 5: Settings Store (TDD)

**Files:**
- Create: `js/store.js`
- Test: `js/store.test.html`

`store.js` wraps `localStorage` with a single namespace prefix (`screenshot-tutor-v1:`). Settings get/set first; sessions in the next task.

- [ ] **Step 1: Write the failing test**

Create `js/store.test.html`:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>store.js unit tests</title>
  <style>
    body { font-family: monospace; padding: 2em; max-width: 900px; }
    .pass { color: green; }
    .fail { color: red; font-weight: bold; }
    pre { background: #f4f4f4; padding: 0.5em; }
  </style>
</head>
<body>
  <h1>store.js — unit tests</h1>
  <div id="out"></div>
  <script type="module">
    import { getSettings, setSettings, KEYS } from './store.js';

    const out = document.getElementById('out');
    let passed = 0, failed = 0;

    function eq(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function assert(name, actual, expected) {
      const ok = eq(actual, expected);
      const line = document.createElement('div');
      line.className = ok ? 'pass' : 'fail';
      line.textContent = (ok ? '✓ ' : '✗ ') + name;
      out.appendChild(line);
      if (!ok) {
        const pre = document.createElement('pre');
        pre.textContent = 'expected: ' + JSON.stringify(expected) + '\n  actual: ' + JSON.stringify(actual);
        out.appendChild(pre);
        failed++;
      } else passed++;
    }
    function reset() { Object.values(KEYS).forEach(k => localStorage.removeItem(k)); }

    // Defaults
    reset();
    assert('settings defaults', getSettings(), { model: 'e4b', lang: 'en', historyOpen: false });

    // Set + persist
    reset();
    setSettings({ model: 'e2b', lang: 'ja', historyOpen: true });
    assert('settings persisted', getSettings(), { model: 'e2b', lang: 'ja', historyOpen: true });

    // Partial update merges
    reset();
    setSettings({ model: 'e4b', lang: 'en', historyOpen: false });
    setSettings({ lang: 'ja' });
    assert('partial update merges', getSettings(), { model: 'e4b', lang: 'ja', historyOpen: false });

    // Invalid model rejected, stays at default
    reset();
    setSettings({ model: 'bogus' });
    assert('invalid model rejected', getSettings().model, 'e4b');

    // Invalid lang rejected
    reset();
    setSettings({ lang: 'fr' });
    assert('invalid lang rejected', getSettings().lang, 'en');

    // Corrupted JSON falls back to defaults
    reset();
    localStorage.setItem(KEYS.settings, '{not json');
    assert('corrupted JSON falls back', getSettings(), { model: 'e4b', lang: 'en', historyOpen: false });

    const summary = document.createElement('h2');
    summary.textContent = `${passed} passed, ${failed} failed`;
    summary.style.color = failed ? 'red' : 'green';
    out.appendChild(summary);
  </script>
</body>
</html>
```

- [ ] **Step 2: Run test to verify it fails**

Open `http://localhost:8000/js/store.test.html`.
Expected: failures because `store.js` doesn't exist.

- [ ] **Step 3: Implement `js/store.js`**

```js
// js/store.js
// localStorage wrapper. All keys namespaced under screenshot-tutor-v1:*.

export const KEYS = {
  settings: 'screenshot-tutor-v1:settings',
  sessions: 'screenshot-tutor-v1:sessions',
};

const DEFAULT_SETTINGS = { model: 'e4b', lang: 'en', historyOpen: false };

function safeGet(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}
function safeSet(key, value) {
  try { localStorage.setItem(key, value); return true; }
  catch { return false; }
}

function parseJson(raw, fallback) {
  if (!raw) return fallback;
  try {
    const v = JSON.parse(raw);
    return v == null ? fallback : v;
  } catch { return fallback; }
}

function validateSettings(s) {
  const out = { ...DEFAULT_SETTINGS };
  if (s && typeof s === 'object') {
    if (s.model === 'e2b' || s.model === 'e4b') out.model = s.model;
    if (s.lang === 'en' || s.lang === 'ja') out.lang = s.lang;
    if (typeof s.historyOpen === 'boolean') out.historyOpen = s.historyOpen;
  }
  return out;
}

export function getSettings() {
  return validateSettings(parseJson(safeGet(KEYS.settings), DEFAULT_SETTINGS));
}

export function setSettings(patch) {
  const current = getSettings();
  const merged = validateSettings({ ...current, ...patch });
  safeSet(KEYS.settings, JSON.stringify(merged));
  return merged;
}
```

- [ ] **Step 4: Run test to verify it passes**

Reload `http://localhost:8000/js/store.test.html`.
Expected: all 6 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add js/store.js js/store.test.html
git commit -m "feat: settings store with validation"
```

---

## Task 6: Sessions Store + Quota Trimming (TDD)

**Files:**
- Modify: `js/store.js` — add session CRUD + quota trim
- Modify: `js/store.test.html` — add session tests

Sessions are an array of `{id, createdAt, image, imageThumb, summary, breakdown, chat}` ordered newest first, capped at `SESSION_LIMIT = 20`. On every write, if total localStorage size exceeds `QUOTA_BUDGET_BYTES = 4_500_000`, drop the oldest until under budget. On `QuotaExceededError`, drop oldest and retry once.

- [ ] **Step 1: Append session tests to `js/store.test.html`** (insert before the `summary` block)

```js
    // --- Sessions ---
    import * as Store from './store.js';
    function resetSessions() { localStorage.removeItem(KEYS.sessions); }

    // empty by default
    resetSessions();
    assert('sessions empty by default', Store.getSessions(), []);

    // add returns id, getSession finds it
    resetSessions();
    const s1 = Store.addSession({ image: 'data:image/jpeg;base64,a', imageThumb: 'data:image/jpeg;base64,t', summary: 'hello' });
    assert('addSession returns object with id', typeof s1.id, 'string');
    assert('getSession finds it', Store.getSession(s1.id).summary, 'hello');

    // newest first
    resetSessions();
    Store.addSession({ image: 'a', imageThumb: 't', summary: 'first' });
    await new Promise(r => setTimeout(r, 5));
    Store.addSession({ image: 'a', imageThumb: 't', summary: 'second' });
    assert('newest first', Store.getSessions()[0].summary, 'second');

    // updateSession merges
    resetSessions();
    const s2 = Store.addSession({ image: 'a', imageThumb: 't', summary: 'before' });
    Store.updateSession(s2.id, { summary: 'after', breakdown: 'b' });
    const u = Store.getSession(s2.id);
    assert('updateSession merges summary', u.summary, 'after');
    assert('updateSession merges breakdown', u.breakdown, 'b');
    assert('updateSession preserves image', u.image, 'a');

    // deleteSession removes
    resetSessions();
    const s3 = Store.addSession({ image: 'a', imageThumb: 't', summary: 'x' });
    Store.deleteSession(s3.id);
    assert('deleteSession removes', Store.getSession(s3.id), null);

    // cap enforced
    resetSessions();
    for (let i = 0; i < Store.SESSION_LIMIT + 5; i++) {
      Store.addSession({ image: 'tiny', imageThumb: 'tiny', summary: 'n=' + i });
    }
    assert('cap at SESSION_LIMIT', Store.getSessions().length, Store.SESSION_LIMIT);
    assert('newest preserved', Store.getSessions()[0].summary, 'n=' + (Store.SESSION_LIMIT + 4));
    assert('oldest dropped', Store.getSession('n=0'), null);
```

Also update the import line at the top of the script block to include the new exports:

```js
    import {
      getSettings, setSettings, KEYS,
      getSessions, getSession, addSession, updateSession, deleteSession,
      SESSION_LIMIT,
    } from './store.js';
```

And remove the inline `import * as Store` line and rewrite test code to use direct imports:

```js
    resetSessions();
    assert('sessions empty by default', getSessions(), []);

    resetSessions();
    const s1 = addSession({ image: 'data:image/jpeg;base64,a', imageThumb: 'data:image/jpeg;base64,t', summary: 'hello' });
    assert('addSession returns object with id', typeof s1.id, 'string');
    assert('getSession finds it', getSession(s1.id).summary, 'hello');

    resetSessions();
    addSession({ image: 'a', imageThumb: 't', summary: 'first' });
    await new Promise(r => setTimeout(r, 5));
    addSession({ image: 'a', imageThumb: 't', summary: 'second' });
    assert('newest first', getSessions()[0].summary, 'second');

    resetSessions();
    const s2 = addSession({ image: 'a', imageThumb: 't', summary: 'before' });
    updateSession(s2.id, { summary: 'after', breakdown: 'b' });
    const u = getSession(s2.id);
    assert('updateSession merges summary', u.summary, 'after');
    assert('updateSession merges breakdown', u.breakdown, 'b');
    assert('updateSession preserves image', u.image, 'a');

    resetSessions();
    const s3 = addSession({ image: 'a', imageThumb: 't', summary: 'x' });
    deleteSession(s3.id);
    assert('deleteSession removes', getSession(s3.id), null);

    resetSessions();
    for (let i = 0; i < SESSION_LIMIT + 5; i++) {
      addSession({ image: 'tiny', imageThumb: 'tiny', summary: 'n=' + i });
    }
    assert('cap at SESSION_LIMIT', getSessions().length, SESSION_LIMIT);
    assert('newest preserved', getSessions()[0].summary, 'n=' + (SESSION_LIMIT + 4));
```

- [ ] **Step 2: Run test to verify session tests fail**

Reload `http://localhost:8000/js/store.test.html`.
Expected: failures because `getSessions`, `addSession`, etc. aren't exported yet.

- [ ] **Step 3: Append session functions to `js/store.js`**

```js
export const SESSION_LIMIT = 20;
const QUOTA_BUDGET_BYTES = 4_500_000;

function totalLocalStorageBytes() {
  let n = 0;
  for (let i = 0; i < localStorage.length; i++) {
    const k = localStorage.key(i);
    const v = localStorage.getItem(k) || '';
    n += k.length + v.length;
  }
  return n;
}

function readSessions() {
  return parseJson(safeGet(KEYS.sessions), []);
}

function writeSessions(arr) {
  // Trim to cap.
  let trimmed = arr.slice(0, SESSION_LIMIT);
  // Try to write. On quota miss, drop oldest until budget or empty.
  while (true) {
    try {
      localStorage.setItem(KEYS.sessions, JSON.stringify(trimmed));
    } catch (err) {
      if (trimmed.length === 0) throw err;
      trimmed = trimmed.slice(0, trimmed.length - 1);
      continue;
    }
    // Budget check on success.
    if (totalLocalStorageBytes() > QUOTA_BUDGET_BYTES && trimmed.length > 1) {
      trimmed = trimmed.slice(0, trimmed.length - 1);
      continue;
    }
    return trimmed;
  }
}

export function getSessions() { return readSessions(); }

export function getSession(id) {
  return readSessions().find((s) => s.id === id) || null;
}

export function addSession(partial) {
  const session = {
    id: (partial && partial.id) || (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random()),
    createdAt: Date.now(),
    image: '',
    imageThumb: '',
    summary: '',
    breakdown: null,
    chat: [],
    ...(partial || {}),
  };
  const sessions = readSessions();
  sessions.unshift(session);
  writeSessions(sessions);
  return session;
}

export function updateSession(id, patch) {
  const sessions = readSessions();
  const idx = sessions.findIndex((s) => s.id === id);
  if (idx < 0) return null;
  sessions[idx] = { ...sessions[idx], ...patch };
  writeSessions(sessions);
  return sessions[idx];
}

export function deleteSession(id) {
  const sessions = readSessions().filter((s) => s.id !== id);
  writeSessions(sessions);
}
```

- [ ] **Step 4: Run test to verify it passes**

Reload `http://localhost:8000/js/store.test.html`.
Expected: all assertions (settings + sessions) pass.

- [ ] **Step 5: Commit**

```bash
git add js/store.js js/store.test.html
git commit -m "feat: session store with cap and quota trimming"
```

---

## Task 7: Prompts Module (EN)

**Files:**
- Create: `js/prompts.js`

Centralizes the three prompt templates with EN variants. JA variants in a later task.

- [ ] **Step 1: Create `js/prompts.js`**

```js
// js/prompts.js
// Prompt templates for the three operations. Tunable in one place.

const EN = {
  summarize:
    'You are a study tutor. Look at this screenshot and produce a concise ' +
    'study-friendly summary in markdown. Format: a one-sentence TL;DR (bold), ' +
    'then 3-5 key bullet points. Focus on what someone studying this material ' +
    'needs to take away. If it is code, summarize what the code does and the ' +
    'key concept it demonstrates. If it is a problem, identify the problem ' +
    'type and solution approach without giving away the answer. Keep it ' +
    'under 200 words.',

  breakdown: (summary) =>
    'Given the screenshot above and your prior summary, produce a study ' +
    'breakdown in markdown:\n\n' +
    '1. **Key terms** — 3-6 terms or concepts with one-line definitions.\n' +
    '2. **Practice questions** — 2-3 questions that test understanding ' +
    '(not trivia recall). Mark each with difficulty (easy/medium/hard). ' +
    'Provide answers in collapsible sections using ' +
    '`<details><summary>Answer</summary>...</details>`.\n\n' +
    'Your prior summary, for reference:\n\n' + summary,

  chatSystem: (summary) =>
    'You are a study tutor helping a learner understand a screenshot they ' +
    'have shared. The screenshot is above and your earlier summary follows. ' +
    'Answer their follow-up questions clearly and concisely. If they ask for ' +
    'a fact you cannot verify from the screenshot, say so rather than ' +
    'guessing. Match their depth: a short question gets a short answer.\n\n' +
    'Your earlier summary:\n\n' + summary,
};

// JA placeholders. Filled in a later task.
const JA = {
  summarize: EN.summarize,
  breakdown: EN.breakdown,
  chatSystem: EN.chatSystem,
};

const TABLES = { en: EN, ja: JA };

export function summarizePrompt(lang) {
  return (TABLES[lang] || EN).summarize;
}

export function breakdownPrompt(lang, summary) {
  return (TABLES[lang] || EN).breakdown(summary || '');
}

export function chatSystemPrompt(lang, summary) {
  return (TABLES[lang] || EN).chatSystem(summary || '');
}
```

- [ ] **Step 2: Replace the hardcoded prompt in `js/worker.js`**

Find this block in `js/worker.js`:

```js
        // Hardcoded summary prompt for the vertical slice. Replaced in a
        // later task by prompts.js with EN/JA variants.
        const promptText = (lang === 'ja')
          ? 'このスクリーンショットを学習者向けに要約してください。最初に太字で1文のTL;DR、その後に3〜5個の重要なポイントを箇条書きで。200語以内。'
          : 'You are a study tutor. Summarize this screenshot in markdown. First a one-sentence TL;DR (bold), then 3-5 key bullet points. Under 200 words.';
```

Replace with:

```js
        const promptText = summarizePrompt(lang);
```

And add at the top of `js/worker.js`:

```js
import { summarizePrompt } from './prompts.js';
```

- [ ] **Step 3: Manual smoke test**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
Paste a screenshot. Verify the summary still streams and looks similar to before.

- [ ] **Step 4: Commit**

```bash
git add js/prompts.js js/worker.js
git commit -m "feat: extract prompts to prompts.js (EN only)"
```

---

## Task 8: Markdown Renderer Component

**Files:**
- Create: `js/components/markdown.js`

A minimal markdown → HTML renderer that handles `**bold**`, lists, paragraphs, and `<details>` blocks. Streaming-friendly: re-renders the full source on each token. Uses `textContent`/safe DOM construction (no `innerHTML` of arbitrary text) to avoid XSS — but allows raw `<details>`/`<summary>` since those come from the model and are needed for collapsible answers.

**Security note:** since the model output is user-influenced, we can't fully trust raw HTML. The renderer escapes everything except a tiny allowlist (`<details>`, `</details>`, `<summary>`, `</summary>`).

- [ ] **Step 1: Create `js/components/markdown.js`**

```js
// js/components/markdown.js
// Minimal streaming-safe markdown renderer.
// Supports: **bold**, *italic*, `code`, lists (- / 1.), paragraphs, line breaks,
// and a tiny HTML allowlist for <details>/<summary> (for collapsible answers).
// Everything else is escaped.

function escapeHtml(s) {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// After escaping, restore the small allowlist of HTML tags.
function restoreAllowedTags(s) {
  return s
    .replace(/&lt;details&gt;/g, '<details>')
    .replace(/&lt;\/details&gt;/g, '</details>')
    .replace(/&lt;summary&gt;/g, '<summary>')
    .replace(/&lt;\/summary&gt;/g, '</summary>');
}

function inline(s) {
  // **bold**
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  // *italic*
  s = s.replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>');
  // `code`
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  return s;
}

function renderBlocks(src) {
  const lines = src.split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];

    // blank
    if (/^\s*$/.test(line)) { i++; continue; }

    // unordered list
    if (/^\s*-\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*-\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*-\s+/, ''));
        i++;
      }
      out.push('<ul>' + items.map((x) => '<li>' + inline(x) + '</li>').join('') + '</ul>');
      continue;
    }

    // ordered list
    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        items.push(lines[i].replace(/^\s*\d+\.\s+/, ''));
        i++;
      }
      out.push('<ol>' + items.map((x) => '<li>' + inline(x) + '</li>').join('') + '</ol>');
      continue;
    }

    // heading
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      const level = h[1].length;
      out.push('<h' + level + '>' + inline(h[2]) + '</h' + level + '>');
      i++;
      continue;
    }

    // details/summary blocks: pass-through, with inline rendering inside
    if (/^<details>/.test(line) || /^<\/details>/.test(line) ||
        /^<summary>/.test(line) || /^<\/summary>/.test(line)) {
      out.push(inline(line));
      i++;
      continue;
    }

    // paragraph: collect until blank line
    const para = [line];
    i++;
    while (i < lines.length && !/^\s*$/.test(lines[i]) && !/^\s*-\s+/.test(lines[i]) && !/^\s*\d+\.\s+/.test(lines[i])) {
      para.push(lines[i]);
      i++;
    }
    out.push('<p>' + inline(para.join('<br>')) + '</p>');
  }
  return out.join('\n');
}

export function renderMarkdown(src) {
  const escaped = escapeHtml(src || '');
  const restored = restoreAllowedTags(escaped);
  return renderBlocks(restored);
}

// Convenience: replace `el.innerHTML` with the rendered output.
export function setMarkdown(el, src) {
  el.innerHTML = renderMarkdown(src);
}
```

- [ ] **Step 2: Smoke test in app.js**

Modify the `m.type === 'token'` handler in `js/app.js` to render markdown:

Find:
```js
  else if (m.type === 'token') output.textContent += m.text;
```

Replace with:
```js
  else if (m.type === 'token') {
    streamedText += m.text;
    setMarkdown(output, streamedText);
  }
```

Add at the top of `js/app.js`:
```js
import { setMarkdown } from './components/markdown.js';
```

And add `let streamedText = '';` near the other top-level state, plus reset it in the `started` handler:
```js
  else if (m.type === 'started') { streamedText = ''; output.textContent = ''; status.textContent = 'generating…'; }
```

Also change the `output` element from `<pre>` to `<div>` in the `root.innerHTML` template so HTML renders.

- [ ] **Step 3: Update CSS for the rendered markdown div**

Edit `#output` block in `css/app.css`:

```css
#output {
  background: #f4f4f4;
  padding: 1rem;
  border-radius: 4px;
  margin-top: 1rem;
  font-size: 14px;
  min-height: 4rem;
}
#output p { margin: 0 0 0.5em; }
#output ul, #output ol { margin: 0 0 0.5em; padding-left: 1.5em; }
#output strong { font-weight: 600; }
#output code { background: #e0e0e0; padding: 1px 4px; border-radius: 2px; font-family: ui-monospace, monospace; }
#output details { margin: 0.5em 0; }
#output summary { cursor: pointer; color: var(--accent); }
```

- [ ] **Step 4: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
Paste a screenshot. Verify:
- Bold text renders as `<strong>` (not literal `**`)
- Bullet lists render as `<ul>` (not literal `- `)
- HTML escaping works: paste a screenshot of code with `<` and `>` characters, verify they don't break the page

- [ ] **Step 5: Commit**

```bash
git add js/components/markdown.js js/app.js css/app.css
git commit -m "feat: minimal streaming markdown renderer"
```

---

## Task 9: i18n Module (EN/JA UI Strings)

**Files:**
- Create: `js/i18n.js`
- Test: `js/i18n.test.html`

Tiny string table with `t(key, lang)`. Used by all UI components for labels, placeholders, errors.

- [ ] **Step 1: Write the failing test**

Create `js/i18n.test.html`:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>i18n.js unit tests</title>
  <style>
    body { font-family: monospace; padding: 2em; }
    .pass { color: green; } .fail { color: red; font-weight: bold; }
  </style>
</head>
<body>
  <h1>i18n.js — unit tests</h1>
  <div id="out"></div>
  <script type="module">
    import { t } from './i18n.js';

    const out = document.getElementById('out');
    let passed = 0, failed = 0;
    function assert(name, ok) {
      const line = document.createElement('div');
      line.className = ok ? 'pass' : 'fail';
      line.textContent = (ok ? '✓ ' : '✗ ') + name;
      out.appendChild(line);
      if (ok) passed++; else failed++;
    }

    assert('en title exists', typeof t('app.title', 'en') === 'string');
    assert('ja title exists', typeof t('app.title', 'ja') === 'string');
    assert('ja differs from en for app.title', t('app.title', 'en') !== t('app.title', 'ja'));
    assert('unknown lang falls back to en', t('app.title', 'fr') === t('app.title', 'en'));
    assert('unknown key returns key', t('does.not.exist', 'en') === 'does.not.exist');

    const summary = document.createElement('h2');
    summary.textContent = `${passed} passed, ${failed} failed`;
    summary.style.color = failed ? 'red' : 'green';
    out.appendChild(summary);
  </script>
</body>
</html>
```

- [ ] **Step 2: Run test to verify it fails**

Open `http://localhost:8000/js/i18n.test.html`.
Expected: failures because `i18n.js` doesn't exist.

- [ ] **Step 3: Implement `js/i18n.js`**

```js
// js/i18n.js
// Tiny string table for the UI. Output language for the LLM is handled
// separately in prompts.js.

const STRINGS = {
  en: {
    'app.title': 'Screenshot Tutor',
    'empty.heading': 'Paste a screenshot, drop an image, or pick a file',
    'empty.hint': 'Cmd+V to paste · drag from Finder · or click below',
    'empty.pick': 'Pick a file',
    'empty.webgpuRequired': 'WebGPU is required. Use Chrome, Edge, or Arc on Apple Silicon.',
    'topbar.model': 'Model',
    'topbar.lang': 'Output',
    'topbar.history': 'History',
    'topbar.new': 'New',
    'session.summary': 'Summary',
    'session.breakdown': 'Generate study breakdown',
    'session.askPlaceholder': 'Ask a follow-up about this screenshot…',
    'session.send': 'Send',
    'session.cancel': 'Cancel',
    'session.loading': 'Loading model… {pct}%',
    'session.thinking': 'Thinking…',
    'session.errorPaste': "Clipboard didn't contain an image",
    'session.errorDrop': "Dropped item wasn't an image",
    'session.errorWorker': 'Worker error: {error}',
    'session.errorBusy': 'Already generating — wait or cancel first',
    'history.empty': 'No past screenshots yet.',
    'history.delete': 'Delete',
    'history.confirmDelete': 'Delete this screenshot?',
  },
  ja: {
    'app.title': 'スクリーンショット家庭教師',
    'empty.heading': 'スクリーンショットを貼り付けるか、画像をドロップ、ファイル選択',
    'empty.hint': 'Cmd+V で貼り付け · Finder からドラッグ · または下のボタン',
    'empty.pick': 'ファイルを選択',
    'empty.webgpuRequired': 'WebGPU が必要です。Apple Silicon の Chrome / Edge / Arc を使ってください。',
    'topbar.model': 'モデル',
    'topbar.lang': '出力言語',
    'topbar.history': '履歴',
    'topbar.new': '新規',
    'session.summary': '要約',
    'session.breakdown': '学習ブレイクダウンを生成',
    'session.askPlaceholder': 'このスクリーンショットについて質問…',
    'session.send': '送信',
    'session.cancel': 'キャンセル',
    'session.loading': 'モデル読み込み中… {pct}%',
    'session.thinking': '考え中…',
    'session.errorPaste': 'クリップボードに画像がありません',
    'session.errorDrop': 'ドロップされた項目は画像ではありません',
    'session.errorWorker': 'ワーカーエラー: {error}',
    'session.errorBusy': '生成中です — 待つかキャンセルしてください',
    'history.empty': '過去のスクリーンショットはありません',
    'history.delete': '削除',
    'history.confirmDelete': 'このスクリーンショットを削除しますか?',
  },
};

export function t(key, lang) {
  const table = STRINGS[lang] || STRINGS.en;
  let s = table[key];
  if (s == null) s = STRINGS.en[key];
  if (s == null) return key;
  return s;
}

// Convenience interpolation for templates like 'session.loading'.
export function tFmt(key, lang, vars) {
  let s = t(key, lang);
  if (vars) {
    for (const [k, v] of Object.entries(vars)) {
      s = s.replace('{' + k + '}', String(v));
    }
  }
  return s;
}
```

- [ ] **Step 4: Run test to verify it passes**

Reload `http://localhost:8000/js/i18n.test.html`.
Expected: all 5 assertions pass.

- [ ] **Step 5: Commit**

```bash
git add js/i18n.js js/i18n.test.html
git commit -m "feat: i18n string table for UI (EN/JA)"
```

---

## Task 10: Topbar Component

**Files:**
- Create: `js/components/topbar.js`

Renders a top bar with: app title, model picker, language toggle, history toggle button. Reads/writes `store.js` settings. Emits a `topbar-change` custom event on the topbar element when settings change so other components can react.

- [ ] **Step 1: Create `js/components/topbar.js`**

```js
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
    // Re-render the topbar so its labels switch language.
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
```

- [ ] **Step 2: Append topbar styles to `css/app.css`**

```css
.topbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1.5rem;
  border-bottom: 1px solid var(--border);
  background: var(--bg);
  position: sticky;
  top: 0;
  z-index: 10;
}

.topbar-title {
  font-weight: 600;
  font-size: 1.1rem;
}

.topbar-actions {
  display: flex;
  gap: 0.75rem;
  align-items: center;
}

.topbar-actions label {
  display: flex;
  gap: 0.4rem;
  align-items: center;
  font-size: 13px;
  color: var(--muted);
}

.topbar-actions button {
  background: transparent;
  border: 1px solid var(--border);
  padding: 4px 10px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 13px;
}

.topbar-actions button:hover { background: #f4f4f4; }
.topbar-actions select { font-size: 13px; padding: 3px 6px; }
```

- [ ] **Step 3: Mount topbar in app.js (smoke test)**

In `js/app.js`, add at the very top of the script body (replace earlier `root.innerHTML = ...` template structure):

```js
import { installInputHandlers } from './input.js';
import { setMarkdown } from './components/markdown.js';
import { mountTopbar } from './components/topbar.js';
import { getSettings } from './store.js';
import { t } from './i18n.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div id="topbar-root"></div>
  <main class="main">
    <div class="sandbox" id="zone" tabindex="0">
      <p>Paste (Cmd+V), drop, or <button id="pick">pick a file</button>.</p>
      <div id="preview"></div>
      <div id="status" class="muted"></div>
      <div id="output"></div>
      <div id="msg" class="muted"></div>
      <button id="cancel" style="display:none">Cancel</button>
    </div>
  </main>
`;

mountTopbar(document.getElementById('topbar-root'), {
  onNewSession: () => location.reload(),
  onToggleHistory: () => alert('history drawer comes in a later task'),
});
```

(Keep the existing zone/preview/status/output/cancel wiring from Task 4/8 — only the outer template and imports change.)

Also add a `.main` style:

```css
.main { max-width: var(--max-width); margin: 0 auto; padding: 1.5rem; }
```

- [ ] **Step 4: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
- Topbar appears with title, Model selector, Lang selector, History button, New button
- Switch Lang to JA — title changes to "スクリーンショット家庭教師"
- Switch Model to e2b — paste a screenshot; the worker uses e2b model
- Click New — page reloads
- Click History — alerts "history drawer comes in a later task"

- [ ] **Step 5: Commit**

```bash
git add js/components/topbar.js js/app.js css/app.css
git commit -m "feat: topbar with model/lang/history controls"
```

---

## Task 11: Empty State + Session Components

**Files:**
- Create: `js/components/empty-state.js`
- Create: `js/components/session.js`
- Modify: `js/app.js` — replace sandbox with proper components

`empty-state` is a paste/drop/pick zone shown when no session is active. `session` displays the current screenshot + streamed summary. Both consume the worker via callbacks passed in.

- [ ] **Step 1: Create `js/components/empty-state.js`**

```js
// js/components/empty-state.js
// Initial paste/drop/pick zone. Visible when no session is active.

import { installInputHandlers } from '../input.js';
import { t } from '../i18n.js';
import { getSettings } from '../store.js';

export function mountEmptyState(container, { onImage, onError }) {
  const s = getSettings();
  const supportsWebGPU = 'gpu' in navigator;

  container.innerHTML = `
    <div class="empty" id="empty-zone" tabindex="0">
      <h2>${t('empty.heading', s.lang)}</h2>
      <p class="muted">${t('empty.hint', s.lang)}</p>
      <button id="empty-pick" type="button">${t('empty.pick', s.lang)}</button>
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

  return {
    destroy() { handlers.uninstall(); },
  };
}
```

- [ ] **Step 2: Create `js/components/session.js`**

```js
// js/components/session.js
// The current session: screenshot preview + streaming summary.
// Breakdown button + chat UI come in later tasks.

import { setMarkdown } from './markdown.js';
import { t, tFmt } from '../i18n.js';
import { getSettings, addSession, updateSession, getSession } from '../store.js';

export function mountSession(container, { worker, sessionId, onNewSession }) {
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
    else if (m.type === 'done') {
      status.textContent = '';
      cancelBtn.style.display = 'none';
      currentRequestId = null;
      updateSession(sessionId, { summary: streamedText });
    }
    else if (m.type === 'cancelled') {
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

  // Kick off the summary if not already populated.
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
```

- [ ] **Step 3: Replace `js/app.js` with the proper wiring**

```js
// js/app.js
// App bootstrap. Wires topbar + empty state + session.
import { mountTopbar } from './components/topbar.js';
import { mountEmptyState } from './components/empty-state.js';
import { mountSession } from './components/session.js';
import { addSession } from './store.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div id="topbar-root"></div>
  <main class="main" id="main-root"></main>
`;

const main = document.getElementById('main-root');
const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
worker.onerror = (e) => console.error('worker error:', e);

let activeSessionMount = null;
let activeEmptyMount = null;

function showEmpty() {
  if (activeSessionMount) { activeSessionMount.destroy(); activeSessionMount = null; }
  main.innerHTML = '';
  activeEmptyMount = mountEmptyState(main, {
    onImage: (result) => {
      const session = addSession({
        image: result.image,
        imageThumb: result.thumb,
      });
      showSession(session.id);
    },
  });
}

function showSession(sessionId) {
  if (activeEmptyMount) { activeEmptyMount.destroy(); activeEmptyMount = null; }
  if (activeSessionMount) { activeSessionMount.destroy(); }
  main.innerHTML = '';
  activeSessionMount = mountSession(main, { worker, sessionId });
}

mountTopbar(document.getElementById('topbar-root'), {
  onNewSession: showEmpty,
  onToggleHistory: () => alert('history drawer comes in a later task'),
});

showEmpty();
```

- [ ] **Step 4: Append component styles to `css/app.css`**

```css
.empty {
  text-align: center;
  padding: 4rem 2rem;
  border: 2px dashed var(--border);
  border-radius: 12px;
  margin-top: 2rem;
}
.empty.drag-over { border-color: var(--accent); background: var(--accent-bg); }
.empty h2 { margin: 0 0 0.5rem; font-weight: 500; }
.empty button {
  margin-top: 1rem;
  padding: 8px 18px;
  background: var(--accent);
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
}

.session-preview {
  max-width: 100%;
  border: 1px solid var(--border);
  border-radius: 4px;
  display: block;
  margin: 0 auto 1rem;
  max-height: 400px;
  object-fit: contain;
}

.session h2 { font-size: 1rem; font-weight: 600; margin: 1rem 0 0.5rem; color: var(--muted); }

.markdown-out {
  background: #fafafa;
  padding: 1rem 1.25rem;
  border-radius: 6px;
  border: 1px solid var(--border);
  min-height: 3rem;
}
.markdown-out p { margin: 0 0 0.5em; }
.markdown-out p:last-child { margin-bottom: 0; }
.markdown-out ul, .markdown-out ol { margin: 0 0 0.5em; padding-left: 1.5em; }
.markdown-out strong { font-weight: 600; }
.markdown-out code { background: #ececec; padding: 1px 4px; border-radius: 2px; font-family: ui-monospace, monospace; }
.markdown-out details { margin: 0.5em 0; }
.markdown-out summary { cursor: pointer; color: var(--accent); }

.session-actions { margin-top: 1rem; }
.session-actions button {
  padding: 6px 12px;
  border-radius: 4px;
  border: 1px solid var(--border);
  background: transparent;
  cursor: pointer;
}

.error { color: var(--error); }
```

- [ ] **Step 5: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
- Empty state appears with proper styling
- Paste a screenshot → session view replaces empty state, summary streams
- Click "New" in topbar → returns to empty state
- Reload page (after a summary completes) → empty state again (history navigation comes later)

- [ ] **Step 6: Commit**

```bash
git add js/components/empty-state.js js/components/session.js js/app.js css/app.css
git commit -m "feat: split empty-state and session components"
```

---

## Task 12: Worker Breakdown Operation

**Files:**
- Modify: `js/worker.js` — add `breakdown` message handler
- Modify: `js/components/session.js` — add Breakdown button + display

- [ ] **Step 1: Add `breakdown` handler in `js/worker.js`**

In `js/worker.js`, change the import line:

```js
import { summarizePrompt, breakdownPrompt } from './prompts.js';
```

Add a new branch in the `self.onmessage` handler — insert after the `summarize` branch and before the `cancel` branch:

```js
    if (msg.type === 'breakdown') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, image, summary, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which || 'e2b');
        self.postMessage({ type: 'started', requestId });

        const promptText = breakdownPrompt(lang, summary || '');
        const inputs = await buildInputs(image, promptText);

        let eosTokenId;
        try {
          const ids = processor.tokenizer.encode('<end_of_turn>', { add_special_tokens: false });
          if (Array.isArray(ids) && ids.length > 0) eosTokenId = ids[0];
        } catch {}

        const { streamer, flush } = makeStreamer(requestId, eosTokenId);

        await model.generate({
          ...inputs,
          max_new_tokens: 768,
          do_sample: false,
          streamer,
          stopping_criteria: stoppingCriteria,
          ...(eosTokenId ? { eos_token_id: eosTokenId } : {}),
        });
        flush();

        if (cancelRequested) {
          self.postMessage({ type: 'cancelled', requestId });
        } else {
          self.postMessage({ type: 'done', requestId });
        }
      } finally {
        stoppingCriteria = null;
        inFlight = false;
      }
      return;
    }
```

- [ ] **Step 2: Add Breakdown button + display to `js/components/session.js`**

In the `mountSession` function, change the `container.innerHTML` template — insert after the `#session-summary` div, before `.session-actions`:

```html
      <button id="session-breakdown-btn" class="primary" type="button" style="margin-top:1rem">
        ${t('session.breakdown', s.lang)}
      </button>
      <h2 id="session-breakdown-heading" style="display:none">${t('session.breakdown', s.lang)}</h2>
      <div id="session-breakdown" class="markdown-out" style="display:none"></div>
```

Add to the top of `mountSession` after the existing element refs:

```js
  const breakdownBtn = container.querySelector('#session-breakdown-btn');
  const breakdownHeading = container.querySelector('#session-breakdown-heading');
  const breakdownEl = container.querySelector('#session-breakdown');

  if (sess.breakdown) {
    breakdownBtn.style.display = 'none';
    breakdownHeading.style.display = '';
    breakdownEl.style.display = '';
    setMarkdown(breakdownEl, sess.breakdown);
  }
```

Add a state flag and a request-tagging map at the top of `mountSession`:

```js
  let activeOp = null; // 'summarize' | 'breakdown'
  let breakdownText = sess.breakdown || '';
```

Modify `startSummarize` to set `activeOp = 'summarize'` before posting:

```js
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
```

Add `startBreakdown`:

```js
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
```

Modify `onWorkerMessage` to dispatch on `activeOp`:

```js
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
```

- [ ] **Step 3: Add primary button style to `css/app.css`**

```css
button.primary {
  background: var(--accent);
  color: white;
  border: none;
  padding: 8px 18px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
}
button.primary:hover { opacity: 0.9; }
```

- [ ] **Step 4: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
- Paste a screenshot → summary streams as before
- Once summary completes, "Generate study breakdown" button appears below
- Click it → breakdown streams in (key terms + practice questions)
- Reload — both summary and breakdown should still be there (persisted)

- [ ] **Step 5: Commit**

```bash
git add js/worker.js js/components/session.js css/app.css
git commit -m "feat: study breakdown generation"
```

---

## Task 13: Worker Chat Operation + Chat UI

**Files:**
- Modify: `js/worker.js` — add `chat` message handler with multi-turn prompt
- Modify: `js/components/session.js` — add chat history display + input

- [ ] **Step 1: Add chat handler in `js/worker.js`**

Update the import:

```js
import { summarizePrompt, breakdownPrompt, chatSystemPrompt } from './prompts.js';
```

Insert a new branch after `breakdown` and before `cancel`:

```js
    if (msg.type === 'chat') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, image, summary, history, userMessage, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which || 'e2b');
        self.postMessage({ type: 'started', requestId });

        // Build a multi-turn prompt:
        // - System prompt: chatSystemPrompt(lang, summary)
        // - First user turn carries image + system prompt as the "context"
        // - Subsequent turns are text-only Q&A
        // The image is bound to the first user turn so the model continues
        // to "see" it across turns through KV cache reuse during generation.
        const sys = chatSystemPrompt(lang, summary || '');
        const firstUser = sys + '\n\nMy first question: ' +
          (history && history.length > 0 && history[0].role === 'user' ? history[0].text : userMessage);

        // Compose chat as a sequence of role-tagged turns. The image attaches
        // to the first user turn only.
        const turns = [];
        const allHistory = (history || []).slice();
        allHistory.push({ role: 'user', text: userMessage });
        let firstUserSent = false;
        for (const h of allHistory) {
          if (h.role === 'user' && !firstUserSent) {
            turns.push({ role: 'user', content: [
              { type: 'image', image },
              { type: 'text', text: sys + '\n\n' + h.text.trim() },
            ]});
            firstUserSent = true;
          } else if (h.role === 'user') {
            turns.push({ role: 'user', content: [{ type: 'text', text: h.text.trim() }] });
          } else {
            turns.push({ role: 'assistant', content: [{ type: 'text', text: h.text.trim() }] });
          }
        }

        let inputs;
        try {
          inputs = await processor.apply_chat_template(turns, {
            add_generation_prompt: true,
            tokenize: true,
            return_dict: true,
            return_tensors: 'pt',
          });
        } catch (err) {
          self.postMessage({ type: 'warn', message: 'apply_chat_template (chat) failed: ' + err.message });
          // Fallback: manual assembly. Image goes in the first user turn via <image_soft_token>.
          const parts = ['<bos>'];
          let firstSent = false;
          for (const t of turns) {
            const role = t.role === 'assistant' ? 'model' : 'user';
            const text = t.content.map((c) => c.type === 'text' ? c.text : '<image_soft_token>').join('\n');
            parts.push('<start_of_turn>' + role + '\n' + text + '<end_of_turn>\n');
            firstSent = true;
          }
          parts.push('<start_of_turn>model\n');
          const prompt = parts.join('');
          inputs = await processor(prompt, image, null, { add_special_tokens: false });
        }

        let eosTokenId;
        try {
          const ids = processor.tokenizer.encode('<end_of_turn>', { add_special_tokens: false });
          if (Array.isArray(ids) && ids.length > 0) eosTokenId = ids[0];
        } catch {}

        const { streamer, flush } = makeStreamer(requestId, eosTokenId);

        await model.generate({
          ...inputs,
          max_new_tokens: 512,
          do_sample: false,
          streamer,
          stopping_criteria: stoppingCriteria,
          ...(eosTokenId ? { eos_token_id: eosTokenId } : {}),
        });
        flush();

        if (cancelRequested) self.postMessage({ type: 'cancelled', requestId });
        else self.postMessage({ type: 'done', requestId });
      } finally {
        stoppingCriteria = null;
        inFlight = false;
      }
      return;
    }
```

- [ ] **Step 2: Add chat UI to `js/components/session.js`**

Extend the `container.innerHTML` template — insert before `.session-actions`:

```html
      <h2 style="margin-top:2rem">${t('session.askPlaceholder', s.lang).replace('…','')}</h2>
      <div id="session-chat" class="chat"></div>
      <form id="session-chat-form" class="chat-form">
        <input id="session-chat-input" type="text"
               placeholder="${t('session.askPlaceholder', s.lang)}" autocomplete="off">
        <button type="submit" class="primary">${t('session.send', s.lang)}</button>
      </form>
```

Add element refs after the breakdown ones:

```js
  const chatList = container.querySelector('#session-chat');
  const chatForm = container.querySelector('#session-chat-form');
  const chatInput = container.querySelector('#session-chat-input');
```

Render existing chat history if any:

```js
  function renderChat() {
    const current = getSession(sessionId);
    if (!current || !current.chat || current.chat.length === 0) {
      chatList.innerHTML = '';
      return;
    }
    chatList.innerHTML = current.chat.map((m) => `
      <div class="chat-msg chat-${m.role}">
        <div class="chat-role">${m.role === 'user' ? '🧑 You' : '🤖 Tutor'}</div>
        <div class="chat-text"></div>
      </div>
    `).join('');
    const nodes = chatList.querySelectorAll('.chat-text');
    current.chat.forEach((m, i) => setMarkdown(nodes[i], m.text));
  }
  renderChat();
```

Extend state with `chatStreamingEl` and `chatStreamingText`:

```js
  let chatStreamingEl = null;
  let chatStreamingText = '';
```

Add `startChat`:

```js
  async function startChat(userText) {
    const current = getSession(sessionId);
    if (!current) return;

    // Persist user message immediately.
    const newChat = (current.chat || []).slice();
    newChat.push({ role: 'user', text: userText, ts: Date.now() });
    updateSession(sessionId, { chat: newChat });
    renderChat();

    // Add an empty assistant bubble for streaming.
    const bubble = document.createElement('div');
    bubble.className = 'chat-msg chat-assistant';
    bubble.innerHTML = '<div class="chat-role">🤖 Tutor</div><div class="chat-text"></div>';
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
        history: newChat.slice(0, -1), // history *before* this user message
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
```

Extend `onWorkerMessage` token branch:

```js
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
```

Extend `done`/`cancelled` branch:

```js
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
```

- [ ] **Step 3: Add chat styles to `css/app.css`**

```css
.chat { margin: 1rem 0; }
.chat-msg {
  margin-bottom: 0.75rem;
  padding: 0.75rem 1rem;
  border-radius: 8px;
}
.chat-msg.chat-user { background: var(--accent-bg); }
.chat-msg.chat-assistant { background: #fafafa; border: 1px solid var(--border); }
.chat-role { font-size: 12px; color: var(--muted); margin-bottom: 4px; }
.chat-text { font-size: 14px; }
.chat-text p { margin: 0 0 0.5em; }
.chat-text p:last-child { margin-bottom: 0; }

.chat-form { display: flex; gap: 0.5rem; margin-top: 1rem; }
.chat-form input {
  flex: 1;
  padding: 8px 12px;
  border: 1px solid var(--border);
  border-radius: 6px;
  font-size: 14px;
}
.chat-form button { padding: 8px 18px; }
```

- [ ] **Step 4: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
- Paste a screenshot, wait for summary
- Type a follow-up in the chat input → user message appears, then assistant streams a response
- Ask another follow-up → it's added below; previous turns stay visible
- Reload — chat history persists

- [ ] **Step 5: Commit**

```bash
git add js/worker.js js/components/session.js css/app.css
git commit -m "feat: chat follow-ups with multimodal context"
```

---

## Task 14: History Drawer

**Files:**
- Create: `js/components/history.js`
- Modify: `js/app.js` — wire history drawer

- [ ] **Step 1: Create `js/components/history.js`**

```js
// js/components/history.js
// Slide-in left drawer that lists past sessions. Click to load. Delete per-row.

import { getSessions, deleteSession, getSettings, setSettings } from '../store.js';
import { t } from '../i18n.js';

export function mountHistory(container, { onSelect }) {
  const s = getSettings();
  let isOpen = !!s.historyOpen;

  function render() {
    const sessions = getSessions();
    container.innerHTML = `
      <aside class="history ${isOpen ? 'open' : ''}">
        <div class="history-header">
          <h3>${t('topbar.history', s.lang)}</h3>
          <button id="history-close" type="button" aria-label="Close">×</button>
        </div>
        <div class="history-list">
          ${sessions.length === 0
            ? `<p class="muted" style="padding:1rem">${t('history.empty', s.lang)}</p>`
            : sessions.map((sess) => `
                <div class="history-item" data-id="${sess.id}">
                  <img src="${sess.imageThumb || sess.image}" alt="">
                  <div class="history-item-body">
                    <div class="history-item-summary">${(sess.summary || '').slice(0, 80) || '(generating…)'}</div>
                    <div class="history-item-time muted">${new Date(sess.createdAt).toLocaleString()}</div>
                  </div>
                  <button class="history-delete" data-delete="${sess.id}" type="button" aria-label="Delete">×</button>
                </div>
              `).join('')}
        </div>
      </aside>
    `;

    container.querySelector('#history-close').addEventListener('click', () => toggle(false));

    container.querySelectorAll('.history-item').forEach((node) => {
      node.addEventListener('click', (e) => {
        if (e.target.closest('.history-delete')) return;
        const id = node.getAttribute('data-id');
        if (id && onSelect) onSelect(id);
        toggle(false);
      });
    });

    container.querySelectorAll('.history-delete').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const id = btn.getAttribute('data-delete');
        if (id && confirm(t('history.confirmDelete', s.lang))) {
          deleteSession(id);
          render();
        }
      });
    });
  }

  function toggle(next) {
    isOpen = next === undefined ? !isOpen : !!next;
    setSettings({ historyOpen: isOpen });
    render();
  }

  render();

  return {
    open: () => toggle(true),
    close: () => toggle(false),
    toggle: () => toggle(),
    refresh: render,
  };
}
```

- [ ] **Step 2: Wire history drawer in `js/app.js`**

Replace `js/app.js`:

```js
// js/app.js
// App bootstrap. Wires topbar + history drawer + empty state + session.
import { mountTopbar } from './components/topbar.js';
import { mountEmptyState } from './components/empty-state.js';
import { mountSession } from './components/session.js';
import { mountHistory } from './components/history.js';
import { addSession } from './store.js';

const root = document.getElementById('app');
root.innerHTML = `
  <div id="topbar-root"></div>
  <div id="history-root"></div>
  <main class="main" id="main-root"></main>
`;

const main = document.getElementById('main-root');
const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
worker.onerror = (e) => console.error('worker error:', e);

let activeSessionMount = null;
let activeEmptyMount = null;

function showEmpty() {
  if (activeSessionMount) { activeSessionMount.destroy(); activeSessionMount = null; }
  main.innerHTML = '';
  activeEmptyMount = mountEmptyState(main, {
    onImage: (result) => {
      const session = addSession({
        image: result.image,
        imageThumb: result.thumb,
      });
      historyMount.refresh();
      showSession(session.id);
    },
  });
}

function showSession(sessionId) {
  if (activeEmptyMount) { activeEmptyMount.destroy(); activeEmptyMount = null; }
  if (activeSessionMount) { activeSessionMount.destroy(); }
  main.innerHTML = '';
  activeSessionMount = mountSession(main, {
    worker,
    sessionId,
    onAfterUpdate: () => historyMount.refresh(),
  });
}

const historyMount = mountHistory(document.getElementById('history-root'), {
  onSelect: (id) => showSession(id),
});

mountTopbar(document.getElementById('topbar-root'), {
  onNewSession: showEmpty,
  onToggleHistory: () => historyMount.toggle(),
});

showEmpty();
```

(No need to actually call `onAfterUpdate` from `session.js` for v1 — list refreshes when drawer opens because `render()` re-reads from store.)

- [ ] **Step 3: Append history styles to `css/app.css`**

```css
.history {
  position: fixed;
  top: 0;
  left: 0;
  bottom: 0;
  width: 320px;
  background: var(--bg);
  border-right: 1px solid var(--border);
  transform: translateX(-100%);
  transition: transform 0.2s ease;
  z-index: 20;
  display: flex;
  flex-direction: column;
  box-shadow: 2px 0 12px rgba(0,0,0,0.05);
}
.history.open { transform: translateX(0); }

.history-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem;
  border-bottom: 1px solid var(--border);
}
.history-header h3 { margin: 0; font-size: 0.95rem; }
.history-header button {
  background: none;
  border: none;
  font-size: 1.5rem;
  cursor: pointer;
  color: var(--muted);
  line-height: 1;
}

.history-list { overflow-y: auto; flex: 1; }

.history-item {
  display: flex;
  gap: 0.5rem;
  align-items: flex-start;
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--border);
  cursor: pointer;
  position: relative;
}
.history-item:hover { background: #fafafa; }
.history-item img {
  width: 64px;
  height: 48px;
  object-fit: cover;
  border-radius: 4px;
  border: 1px solid var(--border);
  flex-shrink: 0;
}
.history-item-body { flex: 1; min-width: 0; }
.history-item-summary {
  font-size: 13px;
  line-height: 1.4;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.history-item-time { font-size: 11px; margin-top: 2px; }
.history-delete {
  background: none;
  border: none;
  cursor: pointer;
  color: var(--muted);
  font-size: 1.2rem;
  padding: 0 4px;
  line-height: 1;
}
```

- [ ] **Step 4: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
- Paste several screenshots in succession (use New between each, since v1 starts a new session per paste and history fills as you go)
- Click "History" in topbar → drawer slides in from left, listing past sessions with thumbnails
- Click a past session → loads that session into the main area
- Click × on a past session → confirms then deletes it
- Add 25+ sessions over multiple pastes → list caps at 20

- [ ] **Step 5: Commit**

```bash
git add js/components/history.js js/app.js css/app.css
git commit -m "feat: history drawer with thumbnail list and delete"
```

---

## Task 15: Japanese Prompt Variants

**Files:**
- Modify: `js/prompts.js` — fill in JA versions

- [ ] **Step 1: Replace the JA placeholder block in `js/prompts.js`**

Replace this:
```js
// JA placeholders. Filled in a later task.
const JA = {
  summarize: EN.summarize,
  breakdown: EN.breakdown,
  chatSystem: EN.chatSystem,
};
```

With:

```js
const JA = {
  summarize:
    'あなたは学習サポートの家庭教師です。このスクリーンショットを見て、' +
    '学習者向けの簡潔な要約を Markdown で作成してください。' +
    'フォーマット: 1文で太字の TL;DR、その後に 3〜5 個の重要なポイントを箇条書きで。' +
    'これを学んでいる人が押さえるべき要点に絞ってください。' +
    'コードであれば、コードが何をするかと示している重要な概念を要約してください。' +
    '問題であれば、答えを言わずに問題のタイプと解法のアプローチを示してください。' +
    '200語以内に収めてください。',

  breakdown: (summary) =>
    '上のスクリーンショットとあなたの先ほどの要約を踏まえて、' +
    '学習用ブレイクダウンを Markdown で作成してください:\n\n' +
    '1. **重要用語** — 3〜6 個の用語または概念を 1 行の定義つきで。\n' +
    '2. **練習問題** — 理解度を試す問題を 2〜3 問 (単なる暗記の確認ではなく)。' +
    'それぞれ難易度を easy / medium / hard でマークしてください。' +
    '答えは `<details><summary>答え</summary>...</details>` の折りたたみで提供してください。\n\n' +
    '参照用のあなたの先ほどの要約:\n\n' + summary,

  chatSystem: (summary) =>
    'あなたはスクリーンショットを共有してきた学習者を助ける家庭教師です。' +
    'スクリーンショットは上にあり、あなたの先ほどの要約は次の通りです。' +
    '彼らのフォローアップの質問に明確かつ簡潔に答えてください。' +
    'スクリーンショットから確認できない事実については、推測せずにその旨を伝えてください。' +
    '質問の深さに合わせてください: 短い質問には短い答えを。\n\n' +
    'あなたの先ほどの要約:\n\n' + summary,
};
```

- [ ] **Step 2: Manual verification**

Run: `python3 -m http.server 8000 &` then open `http://localhost:8000/`.
- Switch Lang to JA
- Paste a screenshot → summary streams in Japanese
- Click breakdown → breakdown streams in Japanese
- Ask a chat question in Japanese → response in Japanese

- [ ] **Step 3: Commit**

```bash
git add js/prompts.js
git commit -m "feat: Japanese prompt variants"
```

---

## Task 16: Error Handling Polish

**Files:**
- Modify: `js/components/empty-state.js` — paste/drop error toasts
- Modify: `js/app.js` — worker error recovery

- [ ] **Step 1: Add a tiny toast helper to `js/app.js`**

Append at the top (after imports):

```js
function showToast(message, kind) {
  const el = document.createElement('div');
  el.className = 'toast' + (kind ? ' toast-' + kind : '');
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.classList.add('show'), 10);
  setTimeout(() => {
    el.classList.remove('show');
    setTimeout(() => el.remove(), 300);
  }, 4000);
}

window.__showToast = showToast; // expose for empty-state and others
```

In the empty-state import: pass the toast through. Modify the `mountEmptyState` call:

```js
  activeEmptyMount = mountEmptyState(main, {
    onImage: (result) => {
      const session = addSession({
        image: result.image,
        imageThumb: result.thumb,
      });
      historyMount.refresh();
      showSession(session.id);
    },
    onError: (err) => showToast(err, 'error'),
  });
```

- [ ] **Step 2: Recover from worker crash**

In `js/app.js`, replace:

```js
worker.onerror = (e) => console.error('worker error:', e);
```

With:

```js
let worker = createWorker();

function createWorker() {
  const w = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
  w.onerror = (e) => {
    console.error('worker error:', e);
    showToast('Worker crashed; respawning. Click New to retry.', 'error');
    try { w.terminate(); } catch {}
    setTimeout(() => { worker = createWorker(); }, 200);
  };
  return w;
}
```

(Move the `const worker = ...` line from earlier in the file to use this factory. The session and other components hold a reference to the worker passed at mount time, so a respawn requires re-mounting — a "New" click does that.)

- [ ] **Step 3: Add toast styles**

Append to `css/app.css`:

```css
.toast {
  position: fixed;
  bottom: 1.5rem;
  left: 50%;
  transform: translateX(-50%) translateY(50px);
  background: var(--fg);
  color: var(--bg);
  padding: 10px 20px;
  border-radius: 8px;
  font-size: 14px;
  opacity: 0;
  transition: all 0.25s ease;
  z-index: 100;
  box-shadow: 0 4px 12px rgba(0,0,0,0.15);
  max-width: 80%;
}
.toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
.toast-error { background: var(--error); }
```

- [ ] **Step 4: Manual verification**

- Paste plain text → toast: "clipboard didn't contain an image"
- Drop a `.txt` file → toast: "dropped item wasn't an image"
- Crash test: in DevTools console, type `throw new Error('test')` inside the worker (via `worker.postMessage({type:'unknown'})` to trigger the unknown-message error path) — confirm error surfaces in UI without freezing the app
- WebGPU absent: open in Safari → empty state shows the WebGPU-required message

- [ ] **Step 5: Commit**

```bash
git add js/app.js js/components/empty-state.js css/app.css
git commit -m "feat: toasts for paste errors and worker recovery"
```

---

## Task 17: TESTING.md and Final README

**Files:**
- Create: `TESTING.md`
- Modify: `README.md` — update with current state

- [ ] **Step 1: Create `TESTING.md`**

```markdown
# Testing

## Unit tests

Open these in a WebGPU-capable browser served from `python3 -m http.server`:

- `http://localhost:8000/js/store.test.html`
- `http://localhost:8000/js/input.test.html`
- `http://localhost:8000/js/i18n.test.html`

All assertions should be green.

## Manual acceptance checklist (v1)

1. Open `http://localhost:8000/` in Chrome / Edge / Arc on Apple Silicon.
2. **Empty state:** big paste/drop/pick zone is visible.
3. **Paste:** take a screenshot (`Cmd+Shift+4`, hold Ctrl), `Cmd+V` into the page.
   - First time: status shows "loading model… X%" for several minutes.
   - Once loaded: status shows "thinking…" then summary streams in.
4. **Breakdown:** click "Generate study breakdown" → streams a list of key terms + practice questions with collapsible answers.
5. **Chat:** type a follow-up in the chat input → user bubble appears, then assistant bubble streams a response. Ask a second follow-up — both turns stay visible.
6. **Reload:** refresh the page. The current session is gone (returns to empty state) but past sessions are in the History drawer.
7. **History drawer:** click "History" → drawer slides in from left with thumbnail + summary preview for past sessions. Click one → it loads. Click × → confirm → it's deleted.
8. **Language toggle:** switch to JA — UI labels switch. Paste a new screenshot → summary streams in Japanese.
9. **Model toggle:** switch to e2b — paste a screenshot. First load downloads the smaller model (~1.5GB).
10. **Drop:** drag an image file from Finder → loads.
11. **File pick:** click "Pick a file" → file picker opens → select an image → loads.
12. **Error paths:**
    - Paste plain text → toast: "clipboard didn't contain an image".
    - Drop a `.txt` file → toast: "dropped item wasn't an image".
    - Open in Safari → empty state shows "WebGPU is required."
13. **Cancel:** click Cancel mid-generation → status clears, partial output is preserved.
14. **History cap:** add 25+ screenshots → list caps at 20 (newest first).
```

- [ ] **Step 2: Update `README.md`**

```markdown
# Screenshot Tutor

A local-LLM browser app: paste a screenshot, get a study-friendly summary, optionally generate a structured breakdown (key terms + practice questions), or chat with a tutor about the screenshot. Output in English or Japanese.

Runs Gemma 4 multimodal via Transformers.js on WebGPU — no API keys, no server.

## Run

```
python3 -m http.server 8000
# open http://localhost:8000
```

Requires Chrome, Edge, or Arc on Apple Silicon (or any WebGPU-capable machine). First model load downloads ~1.5GB (e2b) or ~3GB (e4b) and is cached for future runs.

## Features

- **Paste / drop / pick** any image → study-friendly summary streams in
- **Generate study breakdown** — key terms + practice questions
- **Chat** — ask follow-ups about the screenshot
- **English / Japanese** output
- **History** — last 20 sessions saved locally; click to revisit
- **Two model sizes** — `e2b` (1.5GB, faster) or `e4b` (3GB, better text reading)

## Architecture

- Static files only (no build, no npm)
- Web Worker hosts the LLM (Transformers.js 4.2.0)
- localStorage for sessions and settings
- Plain ES modules

See `docs/superpowers/specs/2026-04-28-screenshot-tutor-design.md` for the design spec and `docs/superpowers/plans/2026-04-28-screenshot-tutor.md` for the implementation plan.

## Testing

See `TESTING.md`.
```

- [ ] **Step 3: Final smoke test**

Walk through the full TESTING.md acceptance checklist end-to-end.

- [ ] **Step 4: Commit**

```bash
git add TESTING.md README.md
git commit -m "docs: TESTING.md + final README"
```

---

## Self-Review

**Spec coverage** — every section of the design spec maps to a task:

- Architecture / Tech stack → Task 1 (scaffold) + Task 4 (worker)
- File structure → Tasks 1, 2, 3, 5–17
- Data model — settings → Task 5
- Data model — sessions + quota → Task 6
- Worker contract — `load`, `summarize`, `cancel`, `unload` → Task 4
- Worker contract — `breakdown` → Task 12
- Worker contract — `chat` → Task 13
- Prompts EN → Task 7
- Prompts JA → Task 15
- UI layout — empty state + session → Task 11
- UI layout — topbar (model/lang/history toggles) → Task 10
- UI layout — markdown renderer → Task 8
- UI layout — i18n → Task 9
- UI layout — history drawer → Task 14
- Error handling — WebGPU-required, paste/drop errors, quota, worker crash → Tasks 6, 11, 16
- Testing — store/input/i18n unit tests → Tasks 2, 5, 6, 9; TESTING.md → Task 17
- Image normalization → Task 2 (core) + Task 3 (handlers)

**Placeholder scan:** none. Every step has executable code or commands.

**Type consistency:** function names checked across tasks — `normalizeImage`, `installInputHandlers`, `getSettings`/`setSettings`, `addSession`/`updateSession`/`getSession`/`deleteSession`/`getSessions`, `summarizePrompt`/`breakdownPrompt`/`chatSystemPrompt`, `t`/`tFmt`, `mountTopbar`/`mountEmptyState`/`mountSession`/`mountHistory`, `setMarkdown`/`renderMarkdown`. All consistent.

**Highest-risk task:** Task 4 (vertical slice). The multimodal API path is the principal unknown. The `buildInputs` helper tries `apply_chat_template` first and falls back to manual prompt assembly with `<image_soft_token>`. If both paths fail, the engineer needs to consult the model card at `https://huggingface.co/onnx-community/gemma-4-E4B-it-ONNX` and adjust the call shape accordingly. This is documented in the task itself.
