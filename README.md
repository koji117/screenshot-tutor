# Screenshot Tutor

A local-LLM browser app: paste a screenshot, get a study-friendly summary, optionally generate a structured breakdown (key terms + practice questions), or chat with a tutor about the screenshot. Output in English or Japanese.

Runs Gemma 4 multimodal via Transformers.js on WebGPU — no API keys, no server.

## Run

    python3 -m http.server 8000
    # open http://localhost:8000

Requires Chrome, Edge, or Arc on Apple Silicon (or any WebGPU-capable machine). First model load downloads ~1.5GB (e2b) or ~3GB (e4b) and is cached for future runs.

## Features

- **Paste / drop / pick / capture** — four ways to feed in a screenshot, with an in-app region-selection overlay for screen captures
- **Streamed summary** — markdown summary streams in as the model generates
- **Study breakdown** — key terms + practice questions with collapsible answers
- **Follow-up chat** — ask anything about the screenshot, multi-turn
- **English / Japanese** output (UI is bilingual too)
- **History** — last 20 sessions saved locally; click any thumbnail to revisit
- **Two model sizes** — `e2b` (1.5GB, faster) or `e4b` (3GB, better text reading)

## Architecture

- Static files only (no build, no npm)
- Web Worker hosts the LLM (Transformers.js 4.2.0, Gemma 4 multimodal, WebGPU)
- localStorage for sessions and settings (auto-trims under 4.5MB)
- Plain ES modules, no framework

See `docs/superpowers/specs/2026-04-28-screenshot-tutor-design.md` for the design spec, `docs/superpowers/plans/2026-04-28-screenshot-tutor.md` for the implementation plan, and `.impeccable.md` for the design context.

## Testing

See `TESTING.md`.
