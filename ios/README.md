# Screenshot Tutor — iPad / iOS native

Native iPadOS / iOS port of the web app, using **MLX-Swift** for
on-device multimodal inference. Built so the heavier Gemma-class
models that don't fit Safari's per-tab memory budget can run with
proper native memory access (mmap, unified memory, full process RAM).

This directory is independent of the web app at the repo root. They
share only the README design context — code is separate.

## Status

Scaffolded skeleton. Not yet building — needs the Xcode project to
be generated and dependencies pinned. See "First-time setup" below.

## Stack

- **UI:** SwiftUI, iOS / iPadOS 17+
- **Inference:** [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) — Apple's MLX-based LLM/VLM library (split out of `mlx-swift-examples` in late 2025). Provides `MLXVLM`, `MLXLMCommon`, `MLXHuggingFace` as Swift Package products.
- **Models:** mlx-community ports on Hugging Face (Qwen2-VL-2B, SmolVLM, Gemma family as published)
- **Project gen:** [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the Xcode project is reproducible from `project.yml` instead of being a hand-edited binary blob

## First-time setup

```sh
# Install XcodeGen if you don't have it
brew install xcodegen

# From this directory
cd ios
xcodegen generate

# Open in Xcode
open ScreenshotTutor.xcodeproj
```

> **Real device required.** MLX-Swift's Metal kernels do not run in
> the iOS Simulator — simulator Metal returns null for device
> properties MLX needs to construct its allocator, and any GPU touch
> hard-crashes inside `mlx::core::metal::MetalAllocator`. The app
> detects the simulator at runtime and shows a clear error rather
> than crashing, so the simulator is fine for UI smoke-tests but
> can't actually load or run a model. Run on a physical iPad/iPhone.

In Xcode:

1. Select the `ScreenshotTutor` target → **Signing & Capabilities** →
   pick your team. A free Apple ID works for sideloading to your own
   iPad.
2. Plug in the iPad, select it as the run destination.
3. Build & run (⌘R). First launch resolves Swift Package
   dependencies (mlx-swift-lm, swift-huggingface, swift-transformers).
4. On the iPad, allow the developer profile in
   **Settings → General → VPN & Device Management** the first time.

## Initial scope (this branch)

- Pick an image from Photos or Files
- Load a VLM (default: Qwen2-VL-2B-Instruct-4bit, works on any iPad
  with 6GB+ RAM)
- Stream a study summary in markdown
- Show progress while the model downloads / loads

Out of scope for the first commit, deferred:

- Breakdown / chat / synthesis (the full web app feature set)
- Settings persistence
- History
- Japanese localization

These get added once the inference path is proven on real hardware.

## Why MLX-Swift over llama.cpp

- MLX uses Apple's unified-memory architecture directly — model
  weights are mmap'd from disk into the GPU/Neural Engine address
  space, so peak RAM is roughly model size, not 2× model size as in
  the browser path.
- MLX-Swift Examples ship a `VLMEvaluator` that handles the
  text+image processing pipeline; llama.cpp's multimodal story
  (LLaVA-style projection layers) is more limited and doesn't cover
  Qwen2-VL or Gemma-style architectures cleanly.
- MLX-community on HF Hub publishes 4-bit and 8-bit quantized VLMs
  within days of new model releases.

## File layout

```
ios/
├── README.md                       — this file
├── project.yml                     — XcodeGen config (target, deps, sources)
└── ScreenshotTutor/
    ├── ScreenshotTutorApp.swift    — @main entry
    ├── ContentView.swift           — root view (image picker + summary)
    ├── Models/
    │   ├── ModelCatalog.swift      — known VLMs and their HF repo ids
    │   └── VLMRunner.swift         — MLX wrapper: load, evaluate, stream
    ├── Views/
    │   ├── EmptyStateView.swift    — pick / capture entry point
    │   ├── ImagePicker.swift       — PhotosPicker bridge
    │   └── SummaryView.swift       — streaming markdown output
    └── Resources/
        └── Info.plist              — photo library usage strings
```
