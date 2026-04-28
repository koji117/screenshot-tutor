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

// Capture a frame from a screen / window / browser tab via the platform's
// screen-share picker. The user picks what to share; we grab a single frame
// and return a normalizeImage() result. Stops the stream immediately after.
//
// Returns null if the user cancels the picker.
export async function captureScreen() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getDisplayMedia) {
    throw new Error('Screen capture not supported in this browser');
  }
  let stream;
  try {
    stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
  } catch (err) {
    // User cancelled the picker (NotAllowedError / AbortError).
    return null;
  }
  try {
    const track = stream.getVideoTracks()[0];
    if (!track) throw new Error('no video track from screen capture');

    // Prefer ImageCapture.grabFrame() when available (Chromium-based).
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
      // Fallback: drive a hidden <video>, then draw a frame to canvas.
      const video = document.createElement('video');
      video.srcObject = stream;
      video.muted = true;
      await video.play();
      // Wait one frame so videoWidth/Height are populated.
      await new Promise((r) => requestAnimationFrame(r));
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      canvas.getContext('2d').drawImage(video, 0, 0);
      video.pause();
      blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
    }
    if (!blob) throw new Error('failed to encode captured frame');
    return await normalizeImage(blob);
  } finally {
    stream.getTracks().forEach((t) => t.stop());
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
