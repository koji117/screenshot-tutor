# Screenshot Tutor

A local-LLM browser app that takes a screenshot and produces a study-friendly summary, with optional structured breakdown and chat follow-ups. Runs Gemma 4 multimodal via Transformers.js on WebGPU — no API keys, no server.

## Run

```
python3 -m http.server 8000
# open http://localhost:8000
```

Requires Chrome, Edge, or Arc with WebGPU. First model load downloads ~1.5GB (e2b) or ~3GB (e4b) and takes a few minutes.

## Design

See `docs/superpowers/specs/2026-04-28-screenshot-tutor-design.md`.
