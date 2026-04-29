// js/worker.js
// Web Worker that hosts a multimodal vision-language model via
// Transformers.js. Supports multiple model families through a small
// registry — see ./models.js for the id → repo/family mapping.
//
// Verified Transformers.js version: 4.2.0
//
// Adding a model family:
//   1. Add an entry to MODELS in models.js with `family: '<name>'`.
//   2. Implement a FAMILIES['<name>'] entry below with `load()`,
//      `eosTokenStr`, and `manualPrompt(text)` for the apply_chat_template
//      fallback.
//   3. The dispatch in loadModel/buildInputs/makeStreamer is family-keyed
//      and will automatically pick up the new entry.

import {
  AutoProcessor,
  Idefics3ForConditionalGeneration,
  Gemma4ForConditionalGeneration,
  TextStreamer,
  InterruptableStoppingCriteria,
  RawImage,
  env,
} from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.2.0';
import { summarizePrompt, breakdownPrompt, chatSystemPrompt, synthesisPrompt } from './prompts.js';
import { MODELS } from './models.js';

env.allowLocalModels = false;
env.useBrowserCache = true;

// Route model fetches through /hf/* on this origin instead of going
// to huggingface.co directly. This eliminates any CORS variance —
// the browser sees only same-origin responses. _worker.js / src/index.js
// proxies /hf/* to huggingface.co with redirects followed server-side
// and permissive CORS attached. When running locally
// (python3 -m http.server) there is no proxy, so we fall back to the
// direct huggingface.co host.
if (typeof self !== 'undefined' && self.location && self.location.origin) {
  const origin = self.location.origin;
  if (/^https?:\/\/(localhost|127\.0\.0\.1)/.test(origin)) {
    env.remoteHost = 'https://huggingface.co';
  } else {
    env.remoteHost = origin + '/hf';
  }
}

// Per-family loaders / prompt fallbacks / streamer markers. Picked by
// the `family` field on the active model entry from models.js.
const FAMILIES = {
  gemma4: {
    async load(repo, progress_callback) {
      const processor = await AutoProcessor.from_pretrained(repo, { progress_callback });
      const model = await Gemma4ForConditionalGeneration.from_pretrained(repo, {
        dtype: 'q4f16',
        device: 'webgpu',
        progress_callback,
      });
      return { processor, model };
    },
    eosTokenStr: '<end_of_turn>',
    streamerMarkers: ['<end_of_turn>', '<start_of_turn>'],
    manualPrompt(text) {
      return '<bos><start_of_turn>user\n<start_of_image>\n' + text.trim() +
        '<end_of_turn>\n<start_of_turn>model\n';
    },
  },

  smolvlm: {
    async load(repo, progress_callback) {
      const processor = await AutoProcessor.from_pretrained(repo, { progress_callback });
      // SmolVLM is built on Idefics3. Using the explicit class here
      // rather than AutoModelForVision2Seq because the auto resolver
      // in transformers@4.2.0 doesn't always pick the correct class
      // for SmolVLM, which leads to the image being silently dropped
      // and the model generating image-blind text.
      //
      // Mixed precision matches the official SmolVLM Transformers.js
      // demo: vision encoder + embed in fp16, decoder in q4. Picked for
      // memory rather than speed — the goal is fitting iOS Safari.
      const model = await Idefics3ForConditionalGeneration.from_pretrained(repo, {
        dtype: {
          embed_tokens: 'fp16',
          vision_encoder: 'fp16',
          decoder_model_merged: 'q4',
        },
        device: 'webgpu',
        progress_callback,
      });
      return { processor, model };
    },
    eosTokenStr: '<end_of_utterance>',
    streamerMarkers: ['<end_of_utterance>'],
    manualPrompt(text) {
      return 'User:<image>' + text.trim() + '<end_of_utterance>\nAssistant:';
    },
  },
};

let processor = null;
let model = null;
let currentModelId = null;
let currentFamily = null;
let cancelRequested = false;
let stoppingCriteria = null;
let inFlight = false;

// Convert a data URL (or any fetchable URL) to a Transformers.js RawImage.
// Required because the processor's image pipeline expects a RawImage; if you
// pass a raw ImageBitmap, the processor silently ignores it and the model
// receives only text — producing replies like "please provide a screenshot".
//
// 1-entry cache: consecutive ops on the same screenshot (summarize →
// breakdown → chat) reuse the decoded RawImage instead of refetching and
// redecoding the JPEG each time. A 1280x720 RGBA RawImage is ~3.7MB;
// holding one in worker memory is cheap relative to the model.
let cachedImageDataUrl = null;
let cachedImage = null;
async function dataUrlToRawImage(dataUrl) {
  if (dataUrl === cachedImageDataUrl && cachedImage) return cachedImage;
  const res = await fetch(dataUrl);
  const blob = await res.blob();
  const image = await RawImage.fromBlob(blob);
  cachedImageDataUrl = dataUrl;
  cachedImage = image;
  return image;
}

async function loadModel(modelId) {
  if (model && processor && currentModelId === modelId) return;
  const meta = MODELS[modelId];
  if (!meta) throw new Error('unknown model: ' + modelId);
  const family = FAMILIES[meta.family];
  if (!family) throw new Error('unknown family: ' + meta.family);

  // If switching models, drop the previous one before loading the new
  // one to free memory rather than holding both at peak.
  if (model && currentModelId !== modelId) {
    try { if (typeof model.dispose === 'function') await model.dispose(); } catch {}
    model = null;
    processor = null;
    currentModelId = null;
    currentFamily = null;
  }

  const progress_callback = (info) => {
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

  const result = await family.load(meta.repo, progress_callback);
  processor = result.processor;
  model = result.model;
  currentModelId = modelId;
  currentFamily = meta.family;
}

// Build inputs for a single-turn user message containing image + text.
//
// Two-step pattern (Transformers.js multimodal contract):
//   1. apply_chat_template(messages, {add_generation_prompt:true}) returns
//      a prompt STRING with image placeholders inserted by the model's
//      chat template (e.g., <start_of_image>... for Gemma 4 or <image>
//      for SmolVLM).
//   2. processor(promptStr, [images]) tokenizes the text AND processes
//      the images, returning {input_ids, attention_mask, pixel_values}.
//
// Setting tokenize:true on apply_chat_template skips step 2 and silently
// drops the image — that's how an earlier version produced replies like
// "please provide a screenshot." We do the two steps explicitly here.
async function buildInputs(image, text) {
  const family = FAMILIES[currentFamily];
  const messages = [
    {
      role: 'user',
      content: [
        { type: 'image' },
        { type: 'text', text },
      ],
    },
  ];

  let promptStr;
  try {
    promptStr = processor.apply_chat_template(messages, {
      add_generation_prompt: true,
    });
  } catch (err) {
    self.postMessage({
      type: 'warn',
      message: 'apply_chat_template failed, using manual prompt: ' + (err && err.message),
    });
    promptStr = family.manualPrompt(text);
  }

  const inputs = await processor(promptStr, [image]);

  // Surface a warning into the UI rather than the worker console (which
  // is invisible on mobile) when pixel_values are missing — that means
  // the image won't reach the model and we'll get image-blind text.
  if (!inputs.pixel_values) {
    self.postMessage({
      type: 'warn',
      message: 'image was not processed by the model — generation will be text-only',
    });
  }

  return inputs;
}

function getEosTokenId() {
  const family = FAMILIES[currentFamily];
  if (!family) return undefined;
  try {
    const ids = processor.tokenizer.encode(family.eosTokenStr, { add_special_tokens: false });
    if (Array.isArray(ids) && ids.length > 0) return ids[0];
  } catch {}
  return undefined;
}

// Stream generation with end-of-turn buffering AND post-batching. Two
// independent buffers:
//
//   pending     — marker buffer. The TextStreamer can deliver an EOT
//                 marker (e.g. "<end_of_turn>" / "<end_of_utterance>")
//                 in pieces, so we hold up to MAX_MARKER_LEN trailing
//                 chars until we know they are not the start of a marker.
//
//   postBuffer  — postMessage batch buffer. Posting one message per
//                 token (~1-3 chars/token) creates 500+ worker → main
//                 hops per response. We coalesce into ~16ms windows so
//                 the main thread renders at ~60Hz max.
function makeStreamer(requestId) {
  const family = FAMILIES[currentFamily];
  const MARKERS = (family && family.streamerMarkers) || [];
  const MAX_MARKER_LEN = MARKERS.length ? Math.max(...MARKERS.map((m) => m.length)) : 0;
  const POST_INTERVAL_MS = 16;

  let pending = '';
  let turnStopped = false;
  let postBuffer = '';
  let postTimer = null;

  function flushPostBuffer() {
    if (postTimer != null) {
      clearTimeout(postTimer);
      postTimer = null;
    }
    if (postBuffer.length > 0) {
      self.postMessage({ type: 'token', requestId, text: postBuffer });
      postBuffer = '';
    }
  }

  function emit(text) {
    postBuffer += text;
    if (postTimer == null) {
      postTimer = setTimeout(flushPostBuffer, POST_INTERVAL_MS);
    }
  }

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
          if (before) emit(before);
          flushPostBuffer();
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
          emit(out);
        }
      },
    }),
    flush() {
      if (!turnStopped && pending && !cancelRequested) {
        emit(pending);
        pending = '';
      }
      flushPostBuffer();
    },
  };
}

self.onmessage = async (e) => {
  const msg = e.data || {};
  try {
    if (msg.type === 'load') {
      await loadModel(msg.model);
      self.postMessage({ type: 'ready' });
      return;
    }

    if (msg.type === 'summarize') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, imageDataUrl, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which);
        self.postMessage({ type: 'started', requestId });

        const image = await dataUrlToRawImage(imageDataUrl);
        const promptText = summarizePrompt(lang);

        const inputs = await buildInputs(image, promptText);

        const eosTokenId = getEosTokenId();
        const { streamer, flush } = makeStreamer(requestId);

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

    if (msg.type === 'breakdown') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, imageDataUrl, summary, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which);
        self.postMessage({ type: 'started', requestId });

        const image = await dataUrlToRawImage(imageDataUrl);
        const promptText = breakdownPrompt(lang, summary || '');
        const inputs = await buildInputs(image, promptText);

        const eosTokenId = getEosTokenId();
        const { streamer, flush } = makeStreamer(requestId);

        await model.generate({
          ...inputs,
          max_new_tokens: 768,
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

    if (msg.type === 'chat') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, imageDataUrl, summary, history, userMessage, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which);
        self.postMessage({ type: 'started', requestId });

        const image = await dataUrlToRawImage(imageDataUrl);
        const sys = chatSystemPrompt(lang, summary || '');
        const family = FAMILIES[currentFamily];

        // Compose chat as role-tagged turns. The image attaches to the
        // first user turn only via the {type:'image'} placeholder; actual
        // pixel data is supplied to processor() in the second step below.
        const turns = [];
        const allHistory = (history || []).slice();
        allHistory.push({ role: 'user', text: userMessage });
        let firstUserSent = false;
        for (const turn of allHistory) {
          if (turn.role === 'user' && !firstUserSent) {
            turns.push({ role: 'user', content: [
              { type: 'image' },
              { type: 'text', text: sys + '\n\n' + turn.text.trim() },
            ]});
            firstUserSent = true;
          } else if (turn.role === 'user') {
            turns.push({ role: 'user', content: [{ type: 'text', text: turn.text.trim() }] });
          } else {
            turns.push({ role: 'assistant', content: [{ type: 'text', text: turn.text.trim() }] });
          }
        }

        let promptStr;
        try {
          promptStr = processor.apply_chat_template(turns, {
            add_generation_prompt: true,
          });
        } catch (err) {
          self.postMessage({ type: 'warn', message: 'apply_chat_template (chat) failed: ' + err.message });
          // Family-agnostic fallback: each family's manualPrompt covers
          // the simple single-turn case; for multi-turn we just stitch
          // user/assistant turns naively. Multi-turn fallback is rare
          // because apply_chat_template almost always succeeds.
          const parts = [];
          for (const turn of turns) {
            const role = turn.role === 'assistant' ? 'Assistant' : 'User';
            const text = turn.content.map((c) => c.type === 'text' ? c.text : '<image>').join('\n');
            parts.push(role + ': ' + text);
          }
          parts.push('Assistant:');
          promptStr = parts.join('\n');
        }

        const inputs = await processor(promptStr, [image]);

        const eosTokenId = getEosTokenId();
        const { streamer, flush } = makeStreamer(requestId);

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

    if (msg.type === 'synthesize') {
      if (inFlight) {
        self.postMessage({ type: 'error', error: 'busy', requestId: msg.requestId });
        return;
      }
      inFlight = true;
      const { requestId, summaries, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which);
        self.postMessage({ type: 'started', requestId });

        // Text-only path. No image; the source material is the past
        // summaries themselves. We still go through the chat template so
        // role tokens are applied correctly.
        const promptText = synthesisPrompt(lang, summaries || []);
        const messages = [
          { role: 'user', content: [{ type: 'text', text: promptText }] },
        ];

        let promptStr;
        try {
          promptStr = processor.apply_chat_template(messages, {
            add_generation_prompt: true,
          });
        } catch (err) {
          self.postMessage({ type: 'warn', message: 'apply_chat_template (synthesize) failed: ' + (err && err.message) });
          promptStr = 'User: ' + promptText + '\nAssistant:';
        }

        const inputs = await processor(promptStr);

        const eosTokenId = getEosTokenId();
        const { streamer, flush } = makeStreamer(requestId);

        await model.generate({
          ...inputs,
          max_new_tokens: 600,
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
      currentModelId = null;
      currentFamily = null;
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
