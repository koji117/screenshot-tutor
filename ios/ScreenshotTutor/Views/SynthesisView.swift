// SynthesisView.swift
// Cross-session reflection — feeds every session's `summary` to the
// model and asks for themes / connections / strengths / gaps / next
// steps. Text-only path: no image attached, since the source material
// is the past summaries themselves.
//
// Mirrors the web app's `js/components/synthesis.js`. After a
// successful synthesis the user can optionally "archive" past
// sessions (clear them from the list).

import SwiftUI
import MLXLMCommon

struct SynthesisView: View {
    @EnvironmentObject var runner: VLMRunner
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: AppSettings

    /// Notified after a successful clear so the parent can refresh
    /// any history badge / count.
    let onAfterClear: () -> Void

    @State private var streamingOutput: String = ""
    @State private var generationTask: Task<Void, Never>?
    @State private var didSucceed: Bool = false
    @State private var started: Bool = false

    private var summaries: [String] {
        store.sessions.compactMap { s in
            let trimmed = s.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What you have been studying")
                    .font(.title.weight(.semibold))
                Text("Across \(summaries.count) sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if summaries.count < 2 {
                    Text("You need at least 2 past summaries before a synthesis is meaningful.")
                        .foregroundStyle(.secondary)
                } else {
                    statusLine
                    if !streamingOutput.isEmpty {
                        MarkdownView(text: streamingOutput)
                    }
                    if didSucceed {
                        HStack(spacing: 12) {
                            exportButton
                            Button(role: .destructive) {
                                store.clearAll()
                                onAfterClear()
                            } label: {
                                Label("Archive past sessions", systemImage: "tray.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if case .generating = runner.state {
                        Button("Cancel", role: .destructive) { cancel() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
        }
        .onAppear { startSynthesisIfNeeded() }
        .onDisappear { generationTask?.cancel() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runner.state {
        case .loading(let p):
            ProgressView(value: p) {
                Text("Loading model… \(Int(p * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Reading your past sessions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(msg)
                .font(.subheadline)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private func startSynthesisIfNeeded() {
        guard !started, summaries.count >= 2 else { return }
        started = true
        let lang = settings.lang
        let snapshot = summaries
        streamingOutput = ""
        didSucceed = false

        generationTask = Task { @MainActor in
            await runner.loadModel()
            guard case .ready = runner.state else { return }
            let chat: [Chat.Message] = [
                .user(Prompts.synthesize(lang: lang, summaries: snapshot))
            ]
            let stream = runner.generate(chat: chat, maxTokens: 600)
            do {
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    streamingOutput += chunk
                }
                if !Task.isCancelled { didSucceed = true }
            } catch {
                // runner.state already reflects the error
            }
        }
    }

    private func cancel() {
        generationTask?.cancel()
        generationTask = nil
    }

    /// Stage the synthesis markdown alongside copies of every
    /// session's screenshot so saving them all into a vault folder
    /// makes the `![[wikilinks]]` resolve. Mirrors the web app's
    /// "save synthesis + sources" flow.
    @ViewBuilder
    private var exportButton: some View {
        // Re-stage on each render — synthesizes a fresh temp dir per
        // ShareLink mount, which is fine because the file count is
        // small and iOS clears NSTemporaryDirectory on its own.
        // Stage the synthesis markdown plus an `attachments/` folder
        // holding every source screenshot. ShareLink takes the
        // markdown file and the folder as separate items — when the
        // user picks "Save to Files", iOS preserves the folder
        // structure so the inline `![[attachments/...]]` wikilinks
        // resolve in the destination vault.
        if let bundle = try? MarkdownExport.stageSynthesis(
            text: streamingOutput,
            sessions: store.sessions,
            imageURL: { store.imageURL(for: $0) }
        ) {
            ShareLink(
                items: bundle.shareURLs,
                subject: Text("Study synthesis"),
                message: Text("Generated by Screenshot Tutor")
            ) {
                Label("Export to Obsidian", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }
}
