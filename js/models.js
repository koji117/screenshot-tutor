// js/models.js
// Single source of truth for available models. Imported by the worker
// (for loading code) and the main thread (for the topbar dropdown +
// empty-state status). Web Workers can import same-origin modules, so
// keeping the registry in one place avoids drift.
//
// Adding a model: append an entry below, then implement its `family`
// loader/prompt logic in worker.js if a new family is introduced.
//
// `iosCompatible` gates the model in iOS Safari, where the per-tab
// memory budget is roughly 1.5–3GB; the larger Gemma 4 models reliably
// crash the tab partway through load (white page) or trigger a
// memory-pressure reload in PWA mode.

export const MODELS = {
  'smolvlm-256m': {
    repo: 'HuggingFaceTB/SmolVLM-256M-Instruct',
    family: 'smolvlm',
    label: 'SmolVLM 256M',
    sizeMB: 250,
    iosCompatible: true,
    note: 'Tiny — fits any iPad. Lower quality on dense text.',
  },
  'smolvlm-500m': {
    repo: 'HuggingFaceTB/SmolVLM-500M-Instruct',
    family: 'smolvlm',
    label: 'SmolVLM 500M',
    sizeMB: 500,
    iosCompatible: true,
    note: 'Small — better quality than 256M; still fits iPad.',
  },
  'gemma4-e2b': {
    repo: 'onnx-community/gemma-4-E2B-it-ONNX',
    family: 'gemma4',
    label: 'Gemma 4 E2B',
    sizeMB: 1500,
    iosCompatible: false,
    note: 'Strong reading. Desktop only — too big for iPad Safari.',
  },
  'gemma4-e4b': {
    repo: 'onnx-community/gemma-4-E4B-it-ONNX',
    family: 'gemma4',
    label: 'Gemma 4 E4B',
    sizeMB: 3000,
    iosCompatible: false,
    note: 'Best reading. Desktop only — needs lots of memory.',
  },
};

export const MODEL_IDS = Object.keys(MODELS);

// First-time default. Conservative pick that works on Apple Silicon
// desktops and will at least *try* on iPad (will be clamped on iOS via
// the validator).
export const DEFAULT_MODEL = 'gemma4-e2b';

// Where iOS gets clamped when the saved/default model isn't compatible.
// Smallest model ensures the user has a working experience by default.
export const IOS_FALLBACK_MODEL = 'smolvlm-256m';

// Legacy id migration. The original release used bare 'e2b' / 'e4b';
// the registry now uses '<family>-<size>' to leave room for SmolVLM.
const LEGACY_MIGRATIONS = {
  e2b: 'gemma4-e2b',
  e4b: 'gemma4-e4b',
};

export function migrateModelId(id) {
  if (id && Object.prototype.hasOwnProperty.call(LEGACY_MIGRATIONS, id)) {
    return LEGACY_MIGRATIONS[id];
  }
  return id;
}
