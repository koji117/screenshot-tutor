// ContentView.swift
// Top-level view. Two states: empty (no image picked) and active
// (image picked, summary streaming). State transitions on image set
// kick off model load → generate.

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var runner: VLMRunner
    @State private var pickedImage: UIImage?

    var body: some View {
        Group {
            if let image = pickedImage {
                SummaryView(
                    image: image,
                    state: runner.state,
                    text: runner.output,
                    onCancel: { runner.cancelGeneration() },
                    onReset: {
                        runner.cancelGeneration()
                        pickedImage = nil
                    }
                )
                .task(id: image) {
                    await summarize(image: image)
                }
            } else {
                EmptyStateView(pickedImage: $pickedImage)
            }
        }
    }

    private func summarize(image: UIImage) async {
        // Ensure the model is loaded before we generate. loadModel()
        // is cheap if it's already loaded.
        await runner.loadModel()
        guard case .ready = runner.state else { return }
        runner.summarize(image: image, prompt: Self.summarizePrompt)
    }

    /// Mirrors the web app's summarize prompt — same study-tutor
    /// instructions so output style matches across platforms.
    static let summarizePrompt =
        """
        You are a study tutor. Look at this screenshot and produce a concise \
        study-friendly summary in markdown. Format: a one-sentence TL;DR (bold), \
        then 3-5 key bullet points. Focus on what someone studying this material \
        needs to take away. If it is code, summarize what the code does and the \
        key concept it demonstrates. If it is a problem, identify the problem \
        type and solution approach without giving away the answer. Keep it \
        under 200 words.
        """
}
