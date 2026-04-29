// VLMRunner.swift
// Owns the MLX VLM container. Single instance held by the App so the
// model survives view changes and a re-tapped "Summarize" doesn't
// reload weights. UI observes `state` and `output` via @Published.
//
// API matches mlx-swift-lm 3.x:
//   - factory.loadContainer(from:#hubDownloader(), using:#huggingFaceTokenizerLoader(), …)
//   - UserInput(chat: [Chat.Message.user(…, images: [.ciImage(…)])])
//   - container.perform { context in MLXLMCommon.generate(…) } returns AsyncStream<Generation>

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
    @Published private(set) var output: String = ""
    @Published var selectedModelID: String = ModelCatalog.defaultID

    private var container: ModelContainer?
    private var loadedModelID: String?
    private var generationTask: Task<Void, Never>?

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
        // the moment we touch any GPU API. Detect early and bail out
        // with a clear message rather than crashing on Memory.cacheLimit
        // or the model load.
        #if targetEnvironment(simulator)
        state = .failed("MLX-Swift requires a real iPad — the iOS Simulator can't run Metal kernels.")
        return
        #endif

        state = .loading(progress: 0)
        do {
            // Cap the GPU buffer cache on real hardware. iPad's unified
            // memory is shared with the rest of the system; bigger
            // caches don't speed up our single-shot summary path enough
            // to justify the pressure. (Memory.cacheLimit replaces the
            // deprecated MLX.GPU.set(cacheLimit:).)
            Memory.cacheLimit = 256 * 1024 * 1024

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

    /// Run a prompt against the loaded model with a single image.
    /// Streams generated text into `output`. Cancellable via
    /// `cancelGeneration()`.
    func summarize(image: UIImage, prompt: String) {
        generationTask?.cancel()
        output = ""
        state = .generating

        guard let container else {
            state = .failed("model not loaded")
            return
        }

        // Persist the picked image to a temp file so we can pass a URL
        // through the @Sendable container.perform closure. CIImage is
        // not Sendable, so capturing one inside `perform` trips the
        // Swift 6 concurrency checker; URL is Sendable.
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            state = .failed("could not encode image")
            return
        }
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("st-\(UUID().uuidString).jpg")
        do {
            try jpegData.write(to: imageURL)
        } catch {
            state = .failed("could not write image: \(error.localizedDescription)")
            return
        }

        generationTask = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: imageURL) }
            do {
                let stream: AsyncStream<Generation> = try await container.perform {
                    (context: ModelContext) in
                    let userInput = UserInput(
                        chat: [
                            Chat.Message.user(prompt, images: [.url(imageURL)])
                        ]
                    )
                    let lmInput = try await context.processor.prepare(input: userInput)
                    let parameters = GenerateParameters(
                        maxTokens: 512,
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
                        await MainActor.run { self.output += text }
                    }
                }

                if !Task.isCancelled {
                    await MainActor.run { self.state = .ready }
                }
            } catch {
                await MainActor.run {
                    self.state = .failed("generation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        if case .generating = state { state = .ready }
    }

    /// Delete the on-disk weights for a model. If the model is the
    /// currently-loaded one, also drops it from memory so the next
    /// `loadModel()` will re-download.
    func deleteModel(id: String) async {
        cancelGeneration()
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
