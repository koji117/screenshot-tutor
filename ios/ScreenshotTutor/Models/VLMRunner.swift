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
import MLXHuggingFace

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

        state = .loading(progress: 0)
        do {
            // Cap the GPU buffer cache. iPad's unified memory is shared with
            // the rest of the system; bigger caches don't speed up our
            // single-shot summary path enough to justify the pressure.
            MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)

            let container = try await VLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
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

        // Convert UIImage → CIImage for the user-input pipeline. MLX-VLM's
        // UserInput.Image accepts `.ciImage` directly.
        guard let cgImage = image.cgImage else {
            state = .failed("could not read image")
            return
        }
        let ciImage = CIImage(cgImage: cgImage)

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let userInput = UserInput(
                    chat: [
                        Chat.Message.user(prompt, images: [.ciImage(ciImage)])
                    ]
                )

                let stream: AsyncStream<Generation> = try await container.perform {
                    (context: ModelContext) in
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
}
