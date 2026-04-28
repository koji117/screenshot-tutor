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
