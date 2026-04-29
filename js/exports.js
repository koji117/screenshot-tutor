// js/exports.js
// Export sessions and synthesis to markdown files in a directory the user
// picks once (typically claude-obsidian/_raw). The directory handle is
// persisted to IndexedDB so subsequent exports are silent — the File
// System Access API does not allow restoring a path string, only the
// opaque handle.

const DB_NAME = 'screenshot-tutor-v1';
const STORE = 'meta';
const KEY_EXPORT_DIR = 'exportDir';

// --- Tiny IndexedDB wrapper for one-key persistence ---

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function idbGet(key) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readonly');
    const req = tx.objectStore(STORE).get(key);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
}

async function idbSet(key, value) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite');
    tx.objectStore(STORE).put(value, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function idbDelete(key) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite');
    tx.objectStore(STORE).delete(key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

// --- Directory handle lifecycle ---

export function isFileSystemAccessSupported() {
  return typeof window !== 'undefined' && typeof window.showDirectoryPicker === 'function';
}

async function pickExportDir() {
  const handle = await window.showDirectoryPicker({
    id: 'screenshot-tutor-export',
    mode: 'readwrite',
    startIn: 'documents',
  });
  await idbSet(KEY_EXPORT_DIR, handle);
  return handle;
}

// Returns a directory handle with confirmed read-write permission, or
// throws if the user cancels the picker. May prompt the user.
async function ensureExportDir() {
  if (!isFileSystemAccessSupported()) {
    throw new Error('File System Access API not supported in this browser');
  }
  const saved = await idbGet(KEY_EXPORT_DIR);
  if (saved) {
    // Permission for stored handles must be re-checked each session.
    let perm = await saved.queryPermission({ mode: 'readwrite' });
    if (perm !== 'granted') {
      perm = await saved.requestPermission({ mode: 'readwrite' });
    }
    if (perm === 'granted') return saved;
    // Stored handle was revoked or denied — fall through to picker.
  }
  return await pickExportDir();
}

// Force the user to re-pick the export directory (e.g., from a settings UI).
// Currently unused; exposed for future "Change export folder" action.
export async function changeExportDir() {
  await idbDelete(KEY_EXPORT_DIR);
  return await pickExportDir();
}

// --- Filename + markdown construction ---

function pad(n) { return String(n).padStart(2, '0'); }

function timestampParts(ts) {
  const d = new Date(ts);
  return {
    iso: d.toISOString(),
    ymd: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    hm: `${pad(d.getHours())}${pad(d.getMinutes())}`,
    hms: `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`,
  };
}

function slugify(s, maxWords = 5, maxLen = 50) {
  if (!s) return '';
  const words = s
    .replace(/[*`#_[\]()<>]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, maxWords);
  return words
    .join('-')
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, maxLen);
}

function buildSessionFilename(session) {
  const { ymd, hm } = timestampParts(session.createdAt);
  const slug = slugify(session.summary) || 'screenshot';
  return `${ymd}-${hm}-${slug}.md`;
}

function buildSynthesisFilename(ts) {
  const { ymd, hm } = timestampParts(ts);
  return `${ymd}-${hm}-synthesis.md`;
}

// Source screenshots embedded into a synthesis use seconds in the filename
// to avoid collisions when multiple sessions share the same minute, and a
// short id suffix as a final tiebreaker.
function buildSourceImageFilename(src) {
  const { ymd, hms } = timestampParts(src.createdAt);
  const slug = slugify(src.summary) || 'screenshot';
  const idTag = (src.id || '').replace(/[^a-z0-9]/gi, '').slice(0, 6) || 'img';
  return `${ymd}-${hms}-${slug}-${idTag}.jpg`;
}

function frontmatter(props) {
  const lines = ['---'];
  for (const [k, v] of Object.entries(props)) {
    if (Array.isArray(v)) {
      lines.push(`${k}:`);
      for (const item of v) lines.push(`  - ${item}`);
    } else {
      lines.push(`${k}: ${v}`);
    }
  }
  lines.push('---', '');
  return lines.join('\n');
}

function buildSessionMarkdown(session) {
  const { iso } = timestampParts(session.createdAt);
  const fm = frontmatter({
    created: iso,
    source: 'screenshot-tutor',
    tags: ['study', 'screenshot'],
  });

  const lines = [];
  lines.push(`# Screenshot summary`);
  lines.push('');
  lines.push('## Summary');
  lines.push('');
  lines.push(session.summary || '_(no summary)_');

  if (session.breakdown) {
    lines.push('');
    lines.push('## Study breakdown');
    lines.push('');
    lines.push(session.breakdown);
  }

  if (session.chat && session.chat.length > 0) {
    lines.push('');
    lines.push('## Follow-up');
    lines.push('');
    for (const m of session.chat) {
      const role = m.role === 'user' ? 'You' : 'Tutor';
      lines.push(`**${role}:**`);
      lines.push('');
      lines.push(m.text);
      lines.push('');
    }
  }

  return fm + lines.join('\n') + '\n';
}

function buildSynthesisMarkdown(text, sessionCount, imageRefs) {
  const ts = Date.now();
  const { iso } = timestampParts(ts);
  const fm = frontmatter({
    created: iso,
    source: 'screenshot-tutor',
    type: 'synthesis',
    sessions: sessionCount,
    tags: ['study', 'synthesis'],
  });

  const lines = [];
  lines.push('# Study synthesis');
  lines.push('');
  lines.push(`_Across ${sessionCount} sessions_`);
  lines.push('');
  lines.push(text);

  if (imageRefs && imageRefs.length > 0) {
    lines.push('');
    lines.push('---');
    lines.push('');
    lines.push('## Source screenshots');
    lines.push('');
    for (const ref of imageRefs) {
      const date = new Date(ref.createdAt).toLocaleString();
      lines.push(`**${date}**`);
      lines.push('');
      lines.push(`![[${ref.filename}]]`);
      lines.push('');
    }
  }

  return fm + lines.join('\n') + '\n';
}

// --- Public exports ---

async function writeFile(dirHandle, filename, content) {
  const fileHandle = await dirHandle.getFileHandle(filename, { create: true });
  const writable = await fileHandle.createWritable();
  await writable.write(content);
  await writable.close();
}

// Save the session as <ymd>-<hm>-<slug>.md. Returns the filename written.
// The screenshot itself is not exported — only the summary, breakdown,
// and chat content go into the markdown.
export async function exportSession(session) {
  if (!session) throw new Error('no session to export');
  const dir = await ensureExportDir();
  const mdFilename = buildSessionFilename(session);
  const md = buildSessionMarkdown(session);
  await writeFile(dir, mdFilename, md);
  return { mdFilename };
}

// Export the synthesis as <ymd>-<hm>-synthesis.md and write each source
// session's screenshot as a sibling JPG that the markdown references via
// [[wikilink]]. Opening the synthesis in Obsidian then renders the source
// screenshots inline. Sources is the array of snapshots from synthesis.js
// (id, image data URL, summary, createdAt).
export async function exportSynthesis(text, sources) {
  if (!text || !text.trim()) throw new Error('no synthesis to export');
  if (!Array.isArray(sources)) sources = [];
  const dir = await ensureExportDir();

  // Write each source image. Skip silently on per-image failure so the
  // synthesis markdown still saves even if one image is unreadable.
  const imageRefs = [];
  for (const src of sources) {
    if (!src || !src.image) continue;
    const imgFilename = buildSourceImageFilename(src);
    try {
      const blob = await (await fetch(src.image)).blob();
      await writeFile(dir, imgFilename, blob);
      imageRefs.push({
        filename: imgFilename,
        createdAt: src.createdAt,
      });
    } catch {
      // continue
    }
  }

  const ts = Date.now();
  const filename = buildSynthesisFilename(ts);
  const md = buildSynthesisMarkdown(text, sources.length, imageRefs);
  await writeFile(dir, filename, md);
  return { filename, imageCount: imageRefs.length };
}
