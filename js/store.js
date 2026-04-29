// js/store.js
// localStorage wrapper. All keys namespaced under screenshot-tutor-v1:*.

import { MODEL_IDS, DEFAULT_MODEL, migrateModelId } from './models.js';

export const KEYS = {
  settings: 'screenshot-tutor-v1:settings',
  sessions: 'screenshot-tutor-v1:sessions',
};

const DEFAULT_SETTINGS = { model: DEFAULT_MODEL, lang: 'en', historyOpen: false };

export const SESSION_LIMIT = 20;
const QUOTA_BUDGET_BYTES = 4_500_000;

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

// True on iPhone/iPad Safari (incl. iPadOS Safari that reports as Mac).
// Kept for UI hints (e.g. surfacing memory warnings on the model picker)
// but no longer used to gate model selection — users are free to attempt
// any model on iPad and accept the memory risk.
export function isIOS() {
  if (typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent || '';
  if (/iPad|iPhone|iPod/.test(ua)) return true;
  // iPadOS Safari sets UA to Macintosh; distinguish by touch support.
  return /Macintosh/.test(ua) && typeof navigator.maxTouchPoints === 'number'
    && navigator.maxTouchPoints > 1;
}

function validateSettings(s) {
  const out = { ...DEFAULT_SETTINGS };
  if (s && typeof s === 'object') {
    const migrated = migrateModelId(s.model);
    if (MODEL_IDS.includes(migrated)) out.model = migrated;
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
  let trimmed = arr.slice(0, SESSION_LIMIT);
  while (true) {
    try {
      localStorage.setItem(KEYS.sessions, JSON.stringify(trimmed));
    } catch (err) {
      if (trimmed.length === 0) throw err;
      trimmed = trimmed.slice(0, trimmed.length - 1);
      continue;
    }
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
