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

// Grab a single frame from a screen-share stream as a PNG Blob.
async function grabFrameBlob() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getDisplayMedia) {
    throw new Error('Screen capture not supported in this browser');
  }
  let stream;
  try {
    stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
  } catch {
    return null; // user cancelled the picker
  }
  try {
    const track = stream.getVideoTracks()[0];
    if (!track) throw new Error('no video track from screen capture');

    let blob;
    if (typeof ImageCapture !== 'undefined') {
      const cap = new ImageCapture(track);
      const bitmap = await cap.grabFrame();
      const canvas = document.createElement('canvas');
      canvas.width = bitmap.width;
      canvas.height = bitmap.height;
      canvas.getContext('2d').drawImage(bitmap, 0, 0);
      bitmap.close();
      blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
    } else {
      const video = document.createElement('video');
      video.srcObject = stream;
      video.muted = true;
      await video.play();
      await new Promise((r) => requestAnimationFrame(r));
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      canvas.getContext('2d').drawImage(video, 0, 0);
      video.pause();
      blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
    }
    if (!blob) throw new Error('failed to encode captured frame');
    return blob;
  } finally {
    stream.getTracks().forEach((t) => t.stop());
  }
}

// Interactive region picker. Shows the blob in a fullscreen overlay; user
// click-and-drags to select a rectangle. Returns a cropped PNG Blob, the
// original blob if user picks "Use full image", or null if cancelled.
async function selectRegion(blob) {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(blob);
    const overlay = document.createElement('div');
    overlay.className = 'capture-overlay';
    overlay.innerHTML = `
      <div class="capture-toolbar">
        <span class="capture-hint">Drag to select a region · Esc to cancel</span>
        <button type="button" class="capture-confirm" disabled>Use selection</button>
        <button type="button" class="capture-full">Use full image</button>
        <button type="button" class="capture-cancel">Cancel</button>
      </div>
      <div class="capture-canvas-wrap">
        <img class="capture-img" alt="captured screenshot">
        <div class="capture-rect" hidden></div>
      </div>
    `;
    document.body.appendChild(overlay);

    const img = overlay.querySelector('.capture-img');
    const rectEl = overlay.querySelector('.capture-rect');
    const wrap = overlay.querySelector('.capture-canvas-wrap');
    const confirmBtn = overlay.querySelector('.capture-confirm');
    const fullBtn = overlay.querySelector('.capture-full');
    const cancelBtn = overlay.querySelector('.capture-cancel');

    img.src = url;

    let startX = 0, startY = 0;
    let rect = null;
    let dragging = false;

    function cleanup(result) {
      URL.revokeObjectURL(url);
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);
      window.removeEventListener('keydown', onKey);
      overlay.remove();
      resolve(result);
    }

    function pxFromEvent(e) {
      const r = img.getBoundingClientRect();
      const x = Math.max(0, Math.min(r.width, e.clientX - r.left));
      const y = Math.max(0, Math.min(r.height, e.clientY - r.top));
      return { x, y };
    }

    function updateRect() {
      const imgR = img.getBoundingClientRect();
      const wrapR = wrap.getBoundingClientRect();
      rectEl.style.left = (imgR.left - wrapR.left + rect.x) + 'px';
      rectEl.style.top = (imgR.top - wrapR.top + rect.y) + 'px';
      rectEl.style.width = rect.w + 'px';
      rectEl.style.height = rect.h + 'px';
    }

    function onMouseDown(e) {
      e.preventDefault();
      const p = pxFromEvent(e);
      startX = p.x; startY = p.y;
      dragging = true;
      rect = { x: startX, y: startY, w: 0, h: 0 };
      rectEl.hidden = false;
      updateRect();
    }
    function onMouseMove(e) {
      if (!dragging) return;
      const p = pxFromEvent(e);
      rect.x = Math.min(startX, p.x);
      rect.y = Math.min(startY, p.y);
      rect.w = Math.abs(p.x - startX);
      rect.h = Math.abs(p.y - startY);
      updateRect();
    }
    function onMouseUp() {
      if (!dragging) return;
      dragging = false;
      confirmBtn.disabled = !(rect && rect.w > 4 && rect.h > 4);
    }
    function onKey(e) {
      if (e.key === 'Escape') cleanup(null);
      else if (e.key === 'Enter' && !confirmBtn.disabled) confirmBtn.click();
    }

    img.addEventListener('mousedown', onMouseDown);
    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
    window.addEventListener('keydown', onKey);

    fullBtn.addEventListener('click', () => cleanup(blob));
    cancelBtn.addEventListener('click', () => cleanup(null));

    confirmBtn.addEventListener('click', async () => {
      if (!rect || rect.w <= 4 || rect.h <= 4) {
        cleanup(blob);
        return;
      }
      // Scale display-pixel rect to natural-pixel rect for the crop.
      const scaleX = img.naturalWidth / img.clientWidth;
      const scaleY = img.naturalHeight / img.clientHeight;
      const sx = Math.round(rect.x * scaleX);
      const sy = Math.round(rect.y * scaleY);
      const sw = Math.round(rect.w * scaleX);
      const sh = Math.round(rect.h * scaleY);

      const bitmap = await createImageBitmap(blob);
      const canvas = document.createElement('canvas');
      canvas.width = sw;
      canvas.height = sh;
      canvas.getContext('2d').drawImage(bitmap, sx, sy, sw, sh, 0, 0, sw, sh);
      bitmap.close();
      const cropped = await new Promise((r) => canvas.toBlob(r, 'image/png'));
      cleanup(cropped || blob);
    });
  });
}

// Capture a screen/window/tab, then prompt the user to select a region of
// it. Returns a normalizeImage() result for the chosen region (or full image
// if "Use full image" picked). Returns null if the user cancels at any step.
export async function captureScreen() {
  const raw = await grabFrameBlob();
  if (!raw) return null;
  const cropped = await selectRegion(raw);
  if (!cropped) return null;
  return await normalizeImage(cropped);
}

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
