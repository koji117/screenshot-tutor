# Screenshot Tutor — iPad / iOS native

Native iPadOS / iOS implementation of the same Screenshot Tutor
product as the web app at the repo root, using **MLX-Swift** for
on-device multimodal inference. Built specifically so the heavier
Gemma 4 models that don't fit Safari's per-tab memory budget can
run with proper native memory access (mmap, unified memory, full
process RAM) — the entitlements file requests
`com.apple.developer.kernel.increased-memory-limit` and
`extended-virtual-addressing`, so the app gets ~6GB of RAM on
modern iPads instead of the ~2GB Safari grants its tabs.

This directory is independent of the web app at the repo root.
The two share design context (`.impeccable.md`) and an Obsidian
export format, but the code is separate.

## Stack

- **UI:** SwiftUI, iOS / iPadOS 17+, `NavigationSplitView` (sidebar
  + detail layout that auto-collapses on compact widths)
- **Inference:** [`mlx-swift-lm`](https://github.com/ml-explore/mlx-swift-lm)
  — Apple's MLX-based LLM/VLM library (split out of
  `mlx-swift-examples` in late 2025). Provides `MLXVLM` and
  `MLXLMCommon` as Swift Package products.
- **Math typesetting:** [SwiftMath](https://github.com/mgriebling/SwiftMath)
  for `$...$` / `$$...$$` LaTeX in model output. Simple inline
  Greek letters (`\mu`, `\sigma`, etc.) and operators are folded
  to Unicode in `MarkdownView` so they flow inline with bullets;
  complex expressions render via SwiftMath as block math.
- **Models:** Gemma 4 E2B (4-bit) and E4B (4-bit), via
  `mlx-community` ports on Hugging Face. E4B is the default;
  requires the increased-memory entitlement.
- **Project gen:** [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  so the Xcode project is reproducible from `project.yml` rather
  than a hand-edited binary blob. The generated `.xcodeproj` is
  gitignored.

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

> **Real device required.** MLX-Swift's Metal kernels do not run
> in the iOS Simulator — simulator Metal returns null for device
> properties MLX needs to construct its allocator, and any GPU
> touch hard-crashes inside `mlx::core::metal::MetalAllocator`.
> The simulator is fine for SwiftUI smoke-tests but cannot load
> or run a model. Build & run on a physical iPad.

In Xcode:

1. Select the `ScreenshotTutor` target → **Signing & Capabilities**.
   The team is wired in via `project.yml` (`DEVELOPMENT_TEAM`).
   You need a **paid Apple Developer Program team** — the
   `com.apple.developer.kernel.increased-memory-limit` and
   `extended-virtual-addressing` entitlements that let the app
   load Gemma 4 E4B (~3GB) are not signable by free Personal Teams.
2. Plug in the iPad, select it as the run destination.
3. ⌘R. First launch resolves the Swift Package graph
   (`mlx-swift-lm`, `swift-huggingface`, `swift-transformers`,
   `SwiftMath`) — this can take several minutes the first time.
4. On the iPad, allow the developer profile in
   **Settings → General → VPN & Device Management** the first time.
5. In the app, tap **Load model** in the empty-state model panel
   to download weights. First load fetches ~3GB for E4B (or
   ~1.5GB for E2B if you switch in Settings) from Hugging Face.

## Features

Full parity with the web app, plus iPad-native ergonomics:

- **Sidebar + detail** via `NavigationSplitView` — the History
  list is permanently visible alongside the active session on
  iPad regular widths; collapses to a single column with a system
  toggle on iPhone / Slide Over.
- **Four input methods** — pick a screenshot from Photos
  (filtered to the Screenshots album by default), take a photo
  with the camera, paste from clipboard (system `PasteButton` —
  no "Allow Paste" prompt), or drag-and-drop an image from any
  iPadOS app. Photos and Camera respect a `Crop / Use full
  image` preference in Settings; Paste has explicit per-tap
  buttons for both.
- **Region selector** with drag-to-crop + "Use full image"
  escape, auto-skipped when VoiceOver is running (gesture-only
  cropping is inaccessible).
- **Streamed summary** with a TL;DR + bullets + analogy, **study
  breakdown** with collapsible answers, **multi-turn chat** with
  iMessage-style bubbles and a pinned bottom composer.
- **Synthesis** across past sessions with a closed-by-default
  source-list disclosure showing date range, plus
  archive-with-confirmation.
- **Export to Obsidian** via `UIDocumentPickerViewController(forExporting:)`
  so the `.md` file and `attachments/` folder land together in the
  user-picked vault folder.
- **Image zoom** — tap the screenshot in a session for a
  full-screen pinch / pan / double-tap-to-zoom viewer.
- **Settings sheet** with Output language, default image mode
  (crop / full), and Model picker.
- **Keyboard shortcuts** (Magic Keyboard): ⌘N New, ⌘, Settings,
  ⌘E Export, ⌘Return Send chat.
- **Haptics** — selection on row pick, light impact on screenshot
  tap and paste, success on summary / breakdown / synthesis
  completion.
- **English / Japanese** output and UI.

## Performance notes

- Decoded `UIImage`s are cached in `SessionStore` via `NSCache`
  (the screenshot and its thumbnail). Without this, every chunk
  arriving during a streaming generation re-decoded the JPEG
  inside the SwiftUI body recompute.
- Token chunks from the model are coalesced into ~16ms windows
  before they hit `@State`, so SwiftUI re-renders at 60Hz max
  instead of model-token-rate. Same pattern as the web app's
  `worker.js` POST_INTERVAL_MS.
- `MarkdownView` conforms to `Equatable` — call sites use
  `.equatable()` so a keystroke in the chat composer doesn't
  trigger a markdown re-parse on every visible bubble + summary.

## Why MLX-Swift over llama.cpp

- MLX uses Apple's unified-memory architecture directly — model
  weights are mmap'd from disk into the GPU/Neural Engine address
  space, so peak RAM is roughly model size, not 2× model size as
  in the browser path.
- `mlx-swift-lm`'s `VLMModelFactory` handles the text+image
  processing pipeline cleanly; llama.cpp's multimodal story
  (LLaVA-style projection layers) is more limited and doesn't
  cover Qwen2-VL or Gemma-style architectures.
- `mlx-community` on HF Hub publishes 4-bit and 8-bit quantized
  VLMs within days of new model releases.

## Why we don't use `MLXHuggingFace`

`mlx-swift-lm` ships an `MLXHuggingFace` library that provides
the macros `#hubDownloader()` and `#huggingFaceTokenizerLoader()`.
These macros require explicit user trust on first build — and
when trust isn't granted (or fails to register), the resulting
errors aren't pretty. Xcode reports "Missing package product
'MLXVLM'" / "'MLXLMCommon'" cascading across the entire package,
not the actual macro target. Debugging this once was enough.

Instead, `HuggingFaceBridge.swift` inlines hand-written
implementations of `MLXLMCommon.Downloader` and
`MLXLMCommon.TokenizerLoader` that wrap `HuggingFace.HubClient`
and `Tokenizers.AutoTokenizer` respectively. Same behavior as
the macros, no plugin trust step.

## File layout

```
ios/
├── README.md                          ← this file
├── project.yml                        ← XcodeGen config (target, deps, sources, signing)
├── .gitignore                         ← keeps the regenerated .xcodeproj out of git
└── ScreenshotTutor/
    ├── ScreenshotTutorApp.swift       ← @main, @StateObjects for runner / store / settings
    ├── ContentView.swift              ← NavigationSplitView routing
    ├── Models/
    │   ├── AppSettings.swift          ← persisted preferences (lang, default image mode)
    │   ├── HuggingFaceBridge.swift    ← inlined Downloader / TokenizerLoader + cache management
    │   ├── MarkdownExport.swift       ← .md + attachments/ staging for export
    │   ├── ModelCatalog.swift         ← VLMRegistry presets (Gemma 4 E2B / E4B)
    │   ├── Prompts.swift              ← summarize / breakdown / chat / synthesize templates
    │   ├── Session.swift              ← record types
    │   ├── SessionStore.swift         ← JSON-on-disk persistence + NSCache image accessor
    │   └── VLMRunner.swift            ← MLX VLMModelFactory wrapper, streams generated text
    ├── Views/
    │   ├── EmptyStateView.swift       ← inputs + clipboard banner + model panel
    │   ├── HistorySidebar.swift       ← NavigationSplitView leading column
    │   ├── SessionView.swift          ← summary + breakdown + chat with pinned composer
    │   ├── SynthesisView.swift        ← cross-session synthesis with source disclosure
    │   ├── SettingsView.swift         ← Form-based preferences sheet
    │   ├── RegionSelectorView.swift   ← drag-to-crop with VoiceOver auto-skip
    │   ├── ImageZoomView.swift        ← full-screen pinch/pan viewer
    │   ├── MarkdownView.swift         ← lightweight markdown renderer with LaTeX folding
    │   ├── DocumentExporter.swift     ← UIDocumentPicker(forExporting:) bridge
    │   └── CameraPicker.swift         ← UIImagePickerController bridge
    ├── ScreenshotTutor.entitlements   ← increased-memory + extended-virtual-addressing
    └── Resources/
        └── Info.plist                 ← bundle metadata + photo / camera usage strings
```

## Common gotchas

- **Simulator crashes**: don't try to load a model in the
  Simulator. The app shows a clear error rather than crashing,
  but inference is device-only.
- **"Missing package product" after a fresh clone**: regenerate
  the Xcode project — `rm -rf ScreenshotTutor.xcodeproj &&
  xcodegen generate`. Package graph lives in `project.yml`, not
  in the gitignored `.pbxproj`.
- **First-build SPM resolution is slow**: 5+ minutes is normal
  while Xcode pulls `mlx-swift-lm`, `swift-huggingface`,
  `swift-transformers`, and `SwiftMath`.
- **Model download is large**: ~3GB for E4B, ~1.5GB for E2B.
  Cached in the app's documents directory; can be deleted from
  the empty-state model panel ("Delete download" in the Menu).
