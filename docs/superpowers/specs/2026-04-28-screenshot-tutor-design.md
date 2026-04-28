# Screenshot Tutor — Design

**Date:** 2026-04-28
**Status:** Approved (brainstorming → ready for implementation plan)

## Purpose

A personal study tutor web app that takes a screenshot (textbook page, slide,
problem, code snippet) and produces a study-friendly summary. The user can
optionally generate a structured breakdown (key terms + practice questions) or
ask follow-up questions about the screenshot in a chat. Output is available in
English or Japanese.

The whole thing runs locally in the browser using Gemma 4 multimodal via
Transformers.js. No API keys, no server, no per-query cost.

## Reference

Patterns and worker shape are adapted from
`/Users/kojisaruya/claude-certificate-study/`, which runs Gemma 4 (text-only)
in a Web Worker on WebGPU. The screenshot-tutor extends this to multimodal
(image + text) input.

## Non-Goals (v1)

- Cross-device sync (no Supabase, no auth)
- PWA install / service worker / offline mode
- Export to file formats (markdown copy button is enough)
- Multi-screenshot sessions (one screenshot = one session)
- CPU fallback for browsers without WebGPU

## Architecture

**Stack:**
- Static site, no build step. Served via `python3 -m http.server 8000`.
- Plain ES modules; no React/Vue/bundler.
- One Web Worker (`worker.js`) owns the LLM.
- `localStorage` for history and settings (key prefix `screenshot-tutor-v1`).
- WebGPU required (worker fails fast if `navigator.gpu` is missing).

**LLM:** Gemma 4 multimodal via Transformers.js 4.2.0
- `AutoProcessor` + `Gemma4ForConditionalGeneration`
- `dtype: 'q4f16'`, `device: 'webgpu'`
- Two model sizes user can pick between: `e2b` and `e4b`
- Streamed tokens via `TextStreamer`, with the same end-of-turn buffering
  trick the reference app uses to avoid leaking turn markers into output

**Three operations** the worker exposes (request/response over `postMessage`):
1. `summarize(image, lang)` — generate the initial summary
2. `breakdown(image, summary, lang)` — generate key terms + practice questions
3. `chat(image, summary, history, userMessage, lang)` — answer a follow-up

All three reuse the same loaded model (loaded lazily on first request).

**Known implementation risk** (verify during build, not now): the reference
app bypasses `apply_chat_template` because it broke for text-only Gemma 4.
Multimodal needs the processor to handle image + text together. The exact
`processor()` call shape for image+text input must be tested against the
Gemma 4 model card and against the manual-prompt path the reference uses.

## File Structure

```
screenshot-tutor/
├── index.html              # single page, empty state + chrome
├── manifest.json           # PWA basics so you can pin to dock if you want
├── css/
│   └── app.css             # all styles, no framework
├── js/
│   ├── app.js              # bootstrap: wire components, load settings
│   ├── worker.js           # the LLM worker (Gemma 4 multimodal)
│   ├── store.js            # localStorage CRUD: history, settings
│   ├── i18n.js             # tiny EN/JA string table for UI
│   ├── prompts.js          # the three prompts (summarize/breakdown/chat) in EN+JA
│   └── components/
│       ├── empty-state.js  # paste / drop / pick zone
│       ├── input.js        # paste/drop/file-pick handlers, image normalization
│       ├── session.js      # current screenshot + summary + breakdown + chat
│       ├── history.js      # left drawer with past sessions
│       ├── topbar.js       # model picker, lang toggle, history toggle
│       └── markdown.js     # tiny markdown renderer for summary output
├── icons/                  # favicon, PWA icons
├── docs/superpowers/specs/ # design docs (this file)
├── README.md
└── TESTING.md              # manual test checklist
```

**Why `prompts.js` is its own module:** prompt iteration is the highest-leverage
tuning lever. Changing the summary style or adjusting practice-question
difficulty takes one edit, no component changes.

**Why `input.js` is its own module:** paste/drop/pick + downscaling images is
fiddly and worth unit-testing in isolation.

## Data Model

**Settings** (`localStorage['screenshot-tutor-v1:settings']`) — JSON:

```js
{
  model: 'e2b' | 'e4b',     // default 'e4b'
  lang: 'en' | 'ja',         // default browser locale fallback to 'en'
  historyOpen: boolean       // last drawer state
}
```

**History** (`localStorage['screenshot-tutor-v1:sessions']`) — array, newest
first, capped at 20:

```js
[
  {
    id: string,                   // crypto.randomUUID()
    createdAt: number,            // Date.now()
    image: string,                // JPEG data URL, ≤1280px max edge, q=0.85
    imageThumb: string,           // 240px max edge thumbnail for sidebar list
    summary: string,              // markdown
    breakdown: string | null,     // markdown, generated lazily
    chat: [{role, text, ts}, ...] // empty until user starts asking follow-ups
  },
  ...
]
```

**Image handling:**
- Paste/drop/pick → `<img>` → canvas downscale to max 1280px edge → JPEG
  q=0.85 → data URL
- Thumbnail is a separate downscale to 240px max edge for the sidebar
- Original is not kept; trade-off for staying under the localStorage cap
- 1280px is a starting point; bump to 1536 or 1920 if text legibility on
  dense slides is poor (verify during implementation)

**Storage budget:** 20 sessions × ~250KB per image ≈ 5MB. Tight against the
~5MB localStorage cap. Two safety valves:

1. On every write, if total localStorage size exceeds 4.5MB, drop the oldest
   sessions until under budget.
2. On `QuotaExceededError`, surface a toast and force-trim.

If 5MB ever feels limiting, IndexedDB is the swap. Not in v1.

## Worker Contract

Worker spawned once in `app.js`, stays alive for the tab. Loads the model on
first generate request (lazy).

**Inbound messages** (main → worker):

```js
{ type: 'load',     model: 'e2b'|'e4b' }
{ type: 'summarize', requestId, image: ImageBitmap, lang: 'en'|'ja', model }
{ type: 'breakdown', requestId, image, summary, lang, model }
{ type: 'chat',      requestId, image, summary, history, userMessage, lang, model }
{ type: 'cancel',   requestId }
{ type: 'unload' }
```

`image` is passed as `ImageBitmap` (transferable). For each generate
request, main thread converts the stored data URL to a fresh
`ImageBitmap` via `createImageBitmap(blob)` and transfers it to the
worker via `worker.postMessage(msg, [image])`. Recreating the
`ImageBitmap` per request (vs. caching one and structured-cloning) is
~10–50ms overhead and avoids ownership-transfer foot-guns where the main
thread loses access to a transferred bitmap.

**Outbound messages** (worker → main):

```js
{ type: 'loading',   pct: 0..100 }            // model download progress
{ type: 'ready' }                              // load complete
{ type: 'started',   requestId }               // generation began
{ type: 'token',     requestId, text }         // streamed token chunk
{ type: 'done',      requestId, fullText }     // natural completion
{ type: 'cancelled', requestId }               // user cancelled
{ type: 'error',     requestId, error }        // any failure
```

**Concurrency:** only one `generate` at a time. Second `generate` while one
is in flight rejects with `error: 'busy'`. Main thread disables inputs while
a request is in flight; `busy` should never fire in practice but is a safety
net.

**Cancel semantics:** `cancel` flips a flag and calls
`stoppingCriteria.interrupt()`. The terminal `cancelled` event only fires
after `model.generate()` actually unwinds, so the UI doesn't lie about the
GPU being free.

## Prompts

Three prompts, each with EN and JA variants, in `prompts.js`. First-cut text
below; meant to be tuned post-build.

**Summarize (EN):**
> You are a study tutor. Look at this screenshot and produce a concise
> study-friendly summary in markdown. Format: a one-sentence TL;DR (bold),
> then 3–5 key bullet points. Focus on what someone studying this material
> needs to take away. If it's code, summarize what the code does and the key
> concept it demonstrates. If it's a problem, identify the problem type and
> solution approach without giving away the answer. Keep it under 200 words.

**Breakdown (EN)** — called after summary, given image + the summary text:
> Given the screenshot above and your prior summary, produce a study
> breakdown in markdown:
> 1. **Key terms** — 3–6 terms or concepts with one-line definitions.
> 2. **Practice questions** — 2–3 questions that test understanding (not
>    trivia recall). Mark each with difficulty (easy/medium/hard). Provide
>    answers in collapsible `<details><summary>Answer</summary>...</details>`.

**Chat (EN)** — system prompt; user's turn appended:
> You are a study tutor helping a learner understand a screenshot they've
> shared. The screenshot and your earlier summary are above. Answer their
> follow-up questions clearly and concisely. If they ask for a fact you
> can't verify from the screenshot, say so rather than guessing. Match
> their depth: a short question gets a short answer.

**JA variants:** direct translations with culturally-appropriate phrasing,
drafted during implementation and reviewed before locking in.

## UI Layout

Single-page layout with a collapsible history drawer on the left.

```
┌─────────────────────────────────────────────┐
│  Screenshot Tutor    [Model ▾] [EN/JA] [≡]  │
├─────────────────────────────────────────────┤
│                                             │
│   ┌─────────────────────────────────┐       │
│   │  [screenshot preview]           │       │
│   └─────────────────────────────────┘       │
│                                             │
│   Summary                                   │
│   ─────────────────                         │
│   Streamed text…                            │
│                                             │
│   [ Generate study breakdown ]              │
│                                             │
│   ┌────────── Ask follow-up ────────┐       │
│   │ [chat history]                  │       │
│   │ [input ____________] [Send]     │       │
│   └─────────────────────────────────┘       │
└─────────────────────────────────────────────┘
```

Empty state when nothing's pasted: large "Paste a screenshot (Cmd+V), drag
an image, or click to pick a file." History drawer hidden behind `≡` button.

**Components and their boundaries:**
- `empty-state` — only visible when no current session; the drop/paste/pick
  zone. Emits a `screenshot-loaded` event with the normalized image.
- `input` — pure logic: paste/drop/file-pick handlers, image normalization
  (downscale + JPEG encode + thumbnail). Has no DOM of its own; consumed by
  `empty-state` and `session`.
- `session` — current screenshot + summary streaming + breakdown button +
  chat. Owns the worker request lifecycle for the active session.
- `history` — left drawer, list of past sessions with thumbnails. Click to
  load a session into `session`. Delete button per row.
- `topbar` — model picker (e2b/e4b), language toggle (EN/JA), history toggle.
- `markdown` — small markdown → DOM renderer for summary/breakdown output.
  Lifted from the reference app. Supports `<details>` for collapsible answers.

## Error Handling

- **No WebGPU** (Safari, older browsers): empty state shows "WebGPU
  required — use Chrome/Edge/Arc on a Mac with Apple Silicon." No degraded
  mode, no CPU fallback.
- **Model download interrupted:** progress bar resets; user can retry.
  HuggingFace CDN handles partial caching.
- **`QuotaExceededError` on history write:** drop oldest sessions until
  write succeeds, surface a toast.
- **Malformed paste** (non-image clipboard content): empty state stays,
  toast says "clipboard didn't contain an image."
- **Worker crash** (`onerror`): show error in current session, kill worker,
  allow retry which respawns it.
- **Generation hangs:** no timeout in v1. Cancel button is the user's
  escape hatch. Watchdog timer is easy to add later if it's an issue.

## Testing

- `js/store.test.html` — pure logic tests for localStorage CRUD, quota
  trimming, history cap (matches the reference app's pattern).
- `js/input.test.html` — image normalization (paste various sizes, verify
  downscale dimensions and format).
- Components and worker: manual browser testing. Headless testing of WebGPU
  + a 3GB model is not worth the time for a personal tool.
- `TESTING.md` with a manual checklist for v1 acceptance: paste an image,
  see summary stream, generate breakdown, ask follow-up, switch language,
  switch model, reload page, see history, click old session, delete session.

## Open Questions / Risks

1. **Multimodal API shape on Gemma 4 in Transformers.js 4.2.0** — the
   reference app's manual-prompt path may or may not work for image+text.
   First implementation step is a vertical slice that proves the worker can
   take an image and produce text. If that fails, fall back to following the
   model card's canonical example exactly.
2. **1280px max edge** may not preserve text legibility on dense slides.
   Verify with a real screenshot during implementation; bump to 1536 or
   1920 if needed.
3. **JA prompt quality** — first-cut translations need a native-speaker
   review pass before locking in.
