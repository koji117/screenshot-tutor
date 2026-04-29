// VLMRunner.swift
// Owns the MLX VLM container. Single instance held by the App so the
// model survives view changes and re-tapping a generate button doesn't
// reload weights.
//
// Public API:
//   loadModel()                                 — download + load into memory
//   generate(chat:maxTokens:) -> AsyncThrowingStream<String,Error>
//                                              — stream chunks of generated text
//   deleteModel(id:)                            — remove on-disk weights
//   diskSize(forID:), isDownloaded(id:)         — UI helpers
//
// The generate API is intentionally generic — callers (SessionView,
// SynthesisView) build the right `[Chat.Message]` for their task
// (summarize / breakdown / chat / synthesize) using `Prompts`.

import Foundation
import SwiftUI
import UIKit
import MLX
import MLXLMCommon
import MLXVLM
// HuggingFaceBridge.swift in this target replaces the macros that
// otherwise ship via MLXHuggingFace. We avoid the macro plugin to
// dodge Xcode's macro-trust prompts and the "Missing package product"
// cascade those produce when the plugin fails to load.

enum VLMRunnerError: LocalizedError {
    case notLoaded
    case simulatorUnsupported

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "Model isn't loaded yet."
        case .simulatorUnsupported:
            return "MLX-Swift requires a real iPad — the iOS Simulator can't run Metal kernels."
        }
    }
}

@MainActor
final class VLMRunner: ObservableObject {

    enum State: Equatable {
        case idle
        case loading(progress: Double)   // 0.0 – 1.0
        case ready
        case generating
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var selectedModelID: String = ModelCatalog.defaultID

    private var container: ModelContainer?
    private var loadedModelID: String?

    // MARK: - Load

    /// Download (if needed) and load the currently-selected model.
    /// Cheap if the model is already loaded.
    func loadModel() async {
        if loadedModelID == selectedModelID, container != nil {
            state = .ready
            return
        }
        guard let entry = ModelCatalog.entry(id: selectedModelID) else {
            state = .failed("unknown model id: \(selectedModelID)")
            return
        }

        // MLX-Swift's Metal kernels don't run in the iOS Simulator —
        // simulator Metal returns a null device-name C string that MLX
        // hands to `std::string`, which crashes inside MetalAllocator
        // the moment we touch any GPU API. Bail out early with a clear
        // message rather than crashing on Memory.cacheLimit / model load.
        #if targetEnvironment(simulator)
        state = .failed(VLMRunnerError.simulatorUnsupported.localizedDescription)
        return
        #endif

        state = .loading(progress: 0)
        do {
            // Squeeze the MLX GPU buffer cache hard — every MB we don't
            // hand to the cache stays available for model weights and
            // activations, which is what gets us under the iOS jetsam
            // ceiling for the larger models (Gemma 4 E4B is ~3GB).
            // 20MB matches Apple's MLXChatExample. The trade-off is a
            // small per-call setup cost; we don't notice it on a single
            // streaming generation.
            Memory.cacheLimit = 20 * 1024 * 1024

            let container = try await VLMModelFactory.shared.loadContainer(
                from: HFDownloader(),
                using: HFTokenizerLoader(),
                configuration: entry.configuration
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .loading(progress: progress.fractionCompleted)
                }
            }
            self.container = container
            self.loadedModelID = selectedModelID
            self.state = .ready
        } catch {
            self.state = .failed("model load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Generate

    /// Stream model output for a chat. The caller is responsible for
    /// composing the right messages (see `Prompts`).
    ///
    /// Cancellation: cancel the consuming Task; the for-await loop
    /// inside this method drops out via `Task.isCancelled` and the
    /// stream finishes cleanly.
    func generate(
        chat: [Chat.Message],
        maxTokens: Int = 512
    ) -> AsyncThrowingStream<String, Error> {
        let container = self.container

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                guard let container else {
                    continuation.finish(throwing: VLMRunnerError.notLoaded)
                    return
                }
                state = .generating
                do {
                    let stream: AsyncStream<Generation> = try await container.perform {
                        (context: ModelContext) in
                        let userInput = UserInput(chat: chat)
                        let lmInput = try await context.processor.prepare(input: userInput)
                        let parameters = GenerateParameters(
                            maxTokens: maxTokens,
                            temperature: 0.0
                        )
                        return try MLXLMCommon.generate(
                            input: lmInput,
                            parameters: parameters,
                            context: context
                        )
                    }

                    for await item in stream {
                        if Task.isCancelled { break }
                        if case .chunk(let text) = item {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                    if case .generating = self.state { self.state = .ready }
                } catch {
                    continuation.finish(throwing: error)
                    if case .generating = self.state {
                        self.state = .failed("generation failed: \(error.localizedDescription)")
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Disk management

    /// Delete the on-disk weights for a model. If the model is the
    /// currently-loaded one, also drops it from memory so the next
    /// `loadModel()` will re-download.
    func deleteModel(id: String) async {
        guard let entry = ModelCatalog.entry(id: id) else { return }

        if loadedModelID == id {
            container = nil
            loadedModelID = nil
            // Reset state so the empty-state UI shows the load button
            // again rather than "Model ready" pointing at vanished weights.
            state = .idle
        }

        do {
            try HFCacheManager.deleteModel(repoID: entry.configuration.name)
        } catch {
            state = .failed("delete failed: \(error.localizedDescription)")
        }
    }

    /// Disk size of the selected model's cached weights, in bytes.
    /// Returns 0 when nothing is cached for that id.
    func diskSize(forID id: String) -> Int64 {
        guard let entry = ModelCatalog.entry(id: id) else { return 0 }
        return HFCacheManager.sizeOnDisk(repoID: entry.configuration.name)
    }

    /// True when the selected model has any weights on disk.
    func isDownloaded(id: String) -> Bool {
        guard let entry = ModelCatalog.entry(id: id) else { return false }
        return HFCacheManager.isDownloaded(repoID: entry.configuration.name)
    }
}
