// SynthesisView.swift
// Cross-session reflection — feeds every session's `summary` to the
// model and asks for themes / connections / strengths / gaps / next
// steps. Text-only path: no image attached, since the source material
// is the past summaries themselves.
//
// Mirrors the web app's `js/components/synthesis.js`. After a
// successful synthesis the user can optionally "archive" past
// sessions (clear them from the list) — this is gated behind a
// `confirmationDialog` because it's destructive and irreversible.

import SwiftUI
import UIKit
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

    /// Holds the staged URLs while the document picker sheet is up.
    /// Restaging on every render would race with the picker's own
    /// file copy, so we freeze the bundle when the user taps export.
    @State private var pendingExport: ExportBundle?

    /// Drives the "Archive past sessions?" confirmation.
    @State private var showArchiveConfirm: Bool = false

    /// Drives the collapsible "Sources" disclosure.
    @State private var sourcesExpanded: Bool = false

    /// Snapshot of which sessions fed the synthesis. Captured once
    /// when generation starts so the source list stays stable even
    /// if the user adds new sessions while reading the synthesis.
    @State private var sourceSessions: [Session] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What you have been studying")
                    .font(.title.weight(.semibold))
                Text("Across \(sourceSessions.count) sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if sourceSessions.count < 2 && !started {
                    Text("You need at least 2 past summaries before a synthesis is meaningful.")
                        .foregroundStyle(.secondary)
                } else {
                    statusLine
                    if !streamingOutput.isEmpty {
                        MarkdownView(text: streamingOutput).equatable()
                    }
                    if didSucceed {
                        sourcesDisclosure
                        actionsRow
                    }
                }
            }
            .padding()
        }
        .onAppear { startSynthesisIfNeeded() }
        .onDisappear { generationTask?.cancel() }
        .toolbar { toolbarContent }
        .sheet(item: Binding(
            get: { pendingExport.map { ExportSheetItem(bundle: $0) } },
            set: { pendingExport = $0?.bundle }
        )) { item in
            DocumentExporter(urls: item.bundle.shareURLs) { _ in
                pendingExport = nil
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Archive these \(sourceSessions.count) sessions?",
            isPresented: $showArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive sessions", role: .destructive) {
                store.clearAll()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onAfterClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The synthesis stays open, but the source sessions are removed from your history. This cannot be undone — export the synthesis first if you want to keep it.")
        }
    }

    /// Wraps the export bundle so SwiftUI's `sheet(item:)` can drive
    /// the picker — `ExportBundle` itself isn't `Identifiable`.
    private struct ExportSheetItem: Identifiable {
        let id = UUID()
        let bundle: ExportBundle
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if case .generating = runner.state {
                Button(role: .destructive) { cancel() } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            } else if didSucceed, !streamingOutput.isEmpty {
                exportToolbarButton
            }
        }
    }

    private var exportToolbarButton: some View {
        Button {
            pendingExport = try? MarkdownExport.stageSynthesis(
                text: streamingOutput,
                sessions: sourceSessions,
                imageURL: { store.imageURL(for: $0) }
            )
        } label: {
            Label("Export to Obsidian", systemImage: "square.and.arrow.down")
        }
        .keyboardShortcut("e", modifiers: .command)
    }

    /// Collapsible list of which sessions the synthesis drew from.
    /// Closed by default — the synthesis prose is the focus; the
    /// sources are a way to verify or revisit, not the main read.
    private var sourcesDisclosure: some View {
        DisclosureGroup(isExpanded: $sourcesExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sourceSessions) { s in
                    sourceRow(s)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text(sourcesLabel)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Sources label includes the date range so the user can see at
    /// a glance which week / period the synthesis spans, e.g.
    /// "Sources · Apr 28 – May 3 · 5 sessions".
    private var sourcesLabel: String {
        let count = sourceSessions.count
        let plural = count == 1 ? "session" : "sessions"
        guard let range = formattedSourceDateRange else {
            return "Sources · \(count) \(plural)"
        }
        return "Sources · \(range) · \(count) \(plural)"
    }

    /// Render the earliest → latest source createdAt as either a
    /// single date (when all sources share a day) or a "Apr 28 –
    /// May 3" range. Locale-aware via `setLocalizedDateFormatFromTemplate`.
    private var formattedSourceDateRange: String? {
        let dates = sourceSessions.map(\.createdAt)
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let from = f.string(from: earliest)
        let to = f.string(from: latest)
        return from == to ? from : "\(from) – \(to)"
    }

    @ViewBuilder
    private func sourceRow(_ s: Session) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let ui = store.thumb(for: s) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate(s.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewText(s.summary))
                    .font(.footnote)
                    .lineLimit(2)
            }
        }
    }

    /// Inline action row shown after a successful synthesis. The
    /// Export button mirrors the toolbar's icon-only version so
    /// the action is discoverable inline; the toolbar version
    /// stays for ⌘E and quick-access. Archive is destructive and
    /// lives only here, with confirmation behind a dialog.
    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button {
                pendingExport = try? MarkdownExport.stageSynthesis(
                    text: streamingOutput,
                    sessions: sourceSessions,
                    imageURL: { store.imageURL(for: $0) }
                )
            } label: {
                Label("Export to Obsidian", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                showArchiveConfirm = true
            } label: {
                Label("Archive past sessions", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runner.state {
        case .loading(let p):
            VStack(alignment: .leading, spacing: 4) {
                Text("Loading model… \(Int(p * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: p)
            }
            .frame(height: 36, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading model")
            .accessibilityValue("\(Int(p * 100)) percent")
            .accessibilityAddTraits(.updatesFrequently)
        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Reading your past sessions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reading your past sessions")
            .accessibilityAddTraits(.updatesFrequently)
        case .failed(let msg):
            HStack(spacing: 10) {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    started = false
                    startSynthesisIfNeeded()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        default:
            EmptyView()
        }
    }

    private func startSynthesisIfNeeded() {
        guard !started else { return }
        let usable = store.sessions.filter {
            !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard usable.count >= 2 else {
            sourceSessions = usable
            return
        }
        started = true
        sourceSessions = usable
        let summaries = usable.map { $0.summary }

        let lang = settings.lang
        streamingOutput = ""
        didSucceed = false

        generationTask = Task { @MainActor in
            await runner.loadModel()
            guard case .ready = runner.state else { return }
            let chat: [Chat.Message] = [
                .user(Prompts.synthesize(lang: lang, summaries: summaries))
            ]
            let stream = runner.generate(chat: chat, maxTokens: 600)
            do {
                // Coalesce token chunks into ~16ms windows so
                // streamingOutput's @State writes don't trigger a
                // markdown re-parse on every token. See SessionView's
                // runStream for the same pattern.
                var pending = ""
                var lastFlush = ContinuousClock.now
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    pending += chunk
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(16) {
                        streamingOutput += pending
                        pending = ""
                        lastFlush = now
                    }
                }
                if !Task.isCancelled, !pending.isEmpty {
                    streamingOutput += pending
                }
                if !Task.isCancelled {
                    didSucceed = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                // runner.state already reflects the error
            }
        }
    }

    private func cancel() {
        generationTask?.cancel()
        generationTask = nil
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func previewText(_ summary: String) -> String {
        let stripped = summary
            .replacingOccurrences(
                of: #"^\s*\*{0,2}TL\s*;\s*DR\s*\*{0,2}\s*[:：]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"[*_`#\[\]()<>]"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "(no summary yet)" : stripped
    }
}
