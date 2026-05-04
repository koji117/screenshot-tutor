# Screenshot Tutor

A study companion that takes a screenshot — textbook page, slide,
code snippet, exam problem — and produces a study-friendly summary,
optional study breakdown, and follow-up chat about it. Output in
English or Japanese. All inference happens on-device: no API keys,
no backend, no network round-trips for generation.

Two implementations of the same product, each on its own branch:

- **Web / PWA** (this branch, `main`) — runs Gemma 4 / SmolVLM via
  Transformers.js on WebGPU. Live at
  [screenshot-tutor.koji11738.workers.dev](https://screenshot-tutor.koji11738.workers.dev/).
- **iPad / iOS native** (`native-ipad-app` branch, in `ios/`) —
  runs Gemma 4 via MLX-Swift with Apple's increased-memory
  entitlements. See [`ios/README.md`](https://github.com/koji117/screenshot-tutor/blob/native-ipad-app/ios/README.md)
  on that branch for build instructions.

The two share design context but no code — see `CLAUDE.md` for the
architectural overview.

## Run the web app locally

```sh
python3 -m http.server 8000
# open http://localhost:8000
```

Requires Chrome, Edge, or Arc on Apple Silicon (or any
WebGPU-capable machine). First model load downloads weights and
caches them for future runs.

## Features

- **Paste / drop / pick / capture** — four ways to feed in a
  screenshot, with an in-app region-selection overlay for screen
  captures
- **Streamed summary** — markdown summary streams in as the model
  generates, with an analogy section that grounds the main idea
  in a familiar everyday situation
- **Study breakdown** — key terms + practice questions with
  collapsible answers
- **Follow-up chat** — ask anything about the screenshot, multi-turn
- **Synthesis** — find themes, gaps, and next steps across past
  sessions; export to Obsidian as a single markdown file with
  source screenshots in an `attachments/` subfolder
- **English / Japanese** output (UI is bilingual too)
- **History** — last 20 sessions saved locally; click any
  thumbnail to revisit
- **LaTeX math** — `$...$` / `$$...$$` from model output is
  typeset via lazily-loaded KaTeX (textbook screenshots often
  produce it)
- **Four models** — pick from a small SmolVLM (fits iPad Safari)
  up to Gemma 4 E4B (best reading on a beefy desktop):
  - `smolvlm-256m` (~250MB) — tiny, fits any iPad; lower quality on dense text
  - `smolvlm-500m` (~500MB) — small; better quality, still fits iPad
  - `gemma4-e2b` (~1.5GB) — strong reading; desktop only
  - `gemma4-e4b` (~3GB) — best reading; desktop only
- **Pre-load** — a "Load model" button on the empty state warms
  the model up before you pick a screenshot, so the first
  generation isn't blocked on a multi-minute download

## Architecture

- Static files only (no build, no npm)
- A Cloudflare Worker (`src/index.js`) serves the static site and
  proxies `/hf/*` to `huggingface.co` so model downloads are
  same-origin (sidesteps CORS variance from third-party model hosts)
- Web Worker (`js/worker.js`) hosts the LLM via Transformers.js 4.2.0
  on WebGPU; model registry in `js/models.js`
- localStorage for sessions and settings (auto-trims under 4.5MB)
- Plain ES modules, no framework

See `docs/superpowers/specs/2026-04-28-screenshot-tutor-design.md`
for the design spec, `docs/superpowers/plans/2026-04-28-screenshot-tutor.md`
for the implementation plan, and `.impeccable.md` for the design
context.

## Deploy (Cloudflare Workers)

The `wrangler.toml` at the repo root binds `src/index.js` as the
Worker entry. Push to `main` and the connected Cloudflare project
auto-deploys.

The `_headers` file configures cache rules (HTML/manifest network-
first; JS/CSS short-cached + must-revalidate; icons immutable). No
COOP/COEP cross-origin isolation is set — adding it would block
loading the model files from `huggingface.co` and the Transformers.js
bundle from `cdn.jsdelivr.net`.

### iPad install (PWA)

Open the deployed URL in **Safari** (not Chrome — iOS PWA install
only works from Safari). Tap the Share button → **Add to Home
Screen** → **Add**. Launch from the Home Screen icon to keep the
cached model through iOS's 7-day storage eviction window. WebGPU
is required; on iPad that means iPadOS 18 or later.

All four models are selectable on iPad, but the larger Gemma 4
options often exceed iOS Safari's per-tab memory budget and either
crash the tab (white page) or trigger a memory-pressure reload
mid-load. If that happens, switch to one of the SmolVLM models —
the 256M variant fits any iPad. For the full Gemma 4 quality on
iPad, build the **native app** from the `native-ipad-app` branch
instead — it gets the increased-memory entitlement and runs
Gemma 4 E4B comfortably.

## Testing

See `TESTING.md`.
