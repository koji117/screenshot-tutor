// SummaryView.swift
// Renders the streaming summary. Markdown rendering uses SwiftUI's
// built-in AttributedString markdown init — good enough for the
// short tutor-style summaries we produce. If we later want
// `<details>` collapsibles for the breakdown view, swap to a real
// markdown renderer (e.g. MarkdownUI).

import SwiftUI
import UIKit

struct SummaryView: View {
    let image: UIImage
    let state: VLMRunner.State
    let text: String
    let onCancel: () -> Void
    let onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                statusLine

                if !text.isEmpty {
                    markdownText
                }

                HStack {
                    if case .generating = state {
                        Button("Cancel", role: .destructive, action: onCancel)
                    } else {
                        Button("New screenshot", action: onReset)
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .idle, .ready:
            EmptyView()
        case .loading(let p):
            ProgressView(value: p) {
                Text("Loading model… \(Int(p * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Thinking…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(msg)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    private var markdownText: some View {
        // AttributedString(markdown:) is per-line; for incremental
        // streaming we just render the whole accumulated buffer each
        // update. SwiftUI diff-renders so this stays cheap.
        let attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
