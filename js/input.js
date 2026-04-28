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
