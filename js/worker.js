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
  RawImage,
  env,
} from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.2.0';
import { summarizePrompt, breakdownPrompt, chatSystemPrompt, synthesisPrompt } from './prompts.js';

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
//
// Two-step pattern (Transformers.js multimodal contract):
//   1. apply_chat_template(messages, {add_generation_prompt:true}) returns
//      a prompt STRING with image placeholders inserted by the Gemma 4
//      chat template (e.g., <start_of_image>...<end_of_image>).
//   2. processor(promptStr, [images]) tokenizes the text AND processes
//      the images, returning {input_ids, attention_mask, pixel_values}.
//
// Setting tokenize:true on apply_chat_template skips step 2 and silently
// drops the image — that's how an earlier version produced replies like
// "please provide a screenshot." We do the two steps explicitly here.
async function buildInputs(image, text) {
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
    promptStr =
      '<bos><start_of_turn>user\n<start_of_image>\n' + text.trim() +
      '<end_of_turn>\n<start_of_turn>model\n';
  }

  const inputs = await processor(promptStr, [image]);

  // Keep one safety log: if the processor didn't compute pixel_values,
  // the model is about to generate text-only, which usually shows up
  // as "please provide a screenshot" replies. Catch it early.
  if (!inputs.pixel_values) {
    console.warn('[buildInputs] NO pixel_values in inputs — image was not processed by the chat template');
  }

  return inputs;
}

// Stream generation with end-of-turn buffering AND post-batching. Two
// independent buffers:
//
//   pending     — marker buffer. The TextStreamer can deliver an EOT
//                 marker like "<end_of_turn>" in pieces, so we hold up
//                 to MAX_MARKER_LEN trailing chars until we know they
//                 are not the start of a marker.
//
//   postBuffer  — postMessage batch buffer. Posting one message per
//                 token (Gemma emits ~1-3 chars/token) creates 500+
//                 worker → main hops per response. We coalesce into
//                 ~16ms windows so the main thread sees ~60 chunks/s
//                 and renders at 60Hz max.
function makeStreamer(requestId, eosTokenId) {
  const MARKERS = ['<end_of_turn>', '<start_of_turn>'];
  const MAX_MARKER_LEN = Math.max(...MARKERS.map((m) => m.length));
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
      const { requestId, imageDataUrl, lang, model: which } = msg;
      try {
        cancelRequested = false;
        stoppingCriteria = new InterruptableStoppingCriteria();
        await loadModel(which || 'e2b');
        self.postMessage({ type: 'started', requestId });

        const image = await dataUrlToRawImage(imageDataUrl);
        const promptText = summarizePrompt(lang);

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
        await loadModel(which || 'e2b');
        self.postMessage({ type: 'started', requestId });

        const image = await dataUrlToRawImage(imageDataUrl);
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
        await loadModel(which || 'e2b');
        self.postMessage({ type: 'started', requestId });

        const image = await dataUrlToRawImage(imageDataUrl);
        const sys = chatSystemPrompt(lang, summary || '');

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
          const parts = ['<bos>'];
          for (const turn of turns) {
            const role = turn.role === 'assistant' ? 'model' : 'user';
            const text = turn.content.map((c) => c.type === 'text' ? c.text : '<start_of_image>').join('\n');
            parts.push('<start_of_turn>' + role + '\n' + text + '<end_of_turn>\n');
          }
          parts.push('<start_of_turn>model\n');
          promptStr = parts.join('');
        }

        const inputs = await processor(promptStr, [image]);

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
        await loadModel(which || 'e2b');
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
          promptStr = '<bos><start_of_turn>user\n' + promptText +
            '<end_of_turn>\n<start_of_turn>model\n';
        }

        const inputs = await processor(promptStr);

        let eosTokenId;
        try {
          const ids = processor.tokenizer.encode('<end_of_turn>', { add_special_tokens: false });
          if (Array.isArray(ids) && ids.length > 0) eosTokenId = ids[0];
        } catch {}

        const { streamer, flush } = makeStreamer(requestId, eosTokenId);

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
