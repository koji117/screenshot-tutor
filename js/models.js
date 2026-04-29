// js/models.js
// Single source of truth for available models. Imported by the worker
// (for loading code) and the main thread (for the topbar dropdown +
// empty-state status). Web Workers can import same-origin modules, so
// keeping the registry in one place avoids drift.
//
// Adding a model: append an entry below, then implement its `family`
// loader/prompt logic in worker.js if a new family is introduced.
//
// The `note` is shown under the model in the empty-state panel and is
// the right place to surface device-fit caveats (e.g. "may not fit on
// iPad Safari") rather than gating selection in the UI — users are
// trusted to decide for their hardware.

export const MODELS = {
  'smolvlm-256m': {
    repo: 'HuggingFaceTB/SmolVLM-256M-Instruct',
    family: 'smolvlm',
    label: 'SmolVLM 256M',
    sizeMB: 250,
    note: 'Tiny — fits any iPad. Lower quality on dense text.',
  },
  'smolvlm-500m': {
    repo: 'HuggingFaceTB/SmolVLM-500M-Instruct',
    family: 'smolvlm',
    label: 'SmolVLM 500M',
    sizeMB: 500,
    note: 'Small — better quality than 256M; still fits iPad.',
  },
  'gemma4-e2b': {
    repo: 'onnx-community/gemma-4-E2B-it-ONNX',
    family: 'gemma4',
    label: 'Gemma 4 E2B',
    sizeMB: 1500,
    note: 'Strong reading. May not fit iPad Safari.',
  },
  'gemma4-e4b': {
    repo: 'onnx-community/gemma-4-E4B-it-ONNX',
    family: 'gemma4',
    label: 'Gemma 4 E4B',
    sizeMB: 3000,
    note: 'Best reading. Desktop-class memory recommended.',
  },
};

export const MODEL_IDS = Object.keys(MODELS);

// First-time default. Strong reading quality on desktop; iPad users
// can switch to a SmolVLM model if Gemma 4 doesn't fit in their
// browser's memory budget.
export const DEFAULT_MODEL = 'gemma4-e2b';

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
