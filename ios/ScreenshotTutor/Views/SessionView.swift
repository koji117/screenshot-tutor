// SessionView.swift
// Active session: screenshot + streaming summary, optional study
// breakdown, and a follow-up chat. Equivalent of the web app's
// `js/components/session.js`. State for the summary/breakdown text
// is held locally during streaming and committed back to the
// SessionStore once the model emits its final chunk.
//
// Layout decisions (see `/polish` UX review for rationale):
//
//   • The chat composer is pinned to the bottom safe area so it's
//     reachable regardless of how long the conversation grows. Mail,
//     Messages, and ChatGPT all use this pattern.
//
//   • Export, Cancel, and Retry actions live in the navigation bar
//     rather than at the bottom of the scroll content — they're
//     chrome, not reading material.
//
//   • Tapping the screenshot opens a full-screen `ImageZoomView`
//     with pinch + pan, so portrait screenshots aren't truncated by
//     the 360pt inline cap.
//
//   • Summary and breakdown each get an overflow Menu with
//     Regenerate / Delete so the user can iterate without backing
//     out of the session.

import SwiftUI
import UIKit
import MLXLMCommon

struct SessionView: View {
    let sessionID: UUID

    @EnvironmentObject var runner: VLMRunner
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: AppSettings

    /// Streaming buffers — populated as token chunks arrive, then
    /// flushed to the SessionStore when the operation completes.
    @State private var streamingSummary: String = ""
    @State private var streamingBreakdown: String = ""
    @State private var streamingChat: String = ""
    @State private var streamingChatMessageID: UUID?

    @State private var chatInput: String = ""
    @State private var generationTask: Task<Void, Never>?
    @State private var summaryStarted: Bool = false

    /// Held while the document picker is presented; see SynthesisView
    /// for the same pattern + rationale.
    @State private var pendingExport: ExportBundle?

    /// Drives the full-screen image viewer.
    @State private var showZoom: Bool = false

    /// Records the last operation kicked off so a "Retry" button on
    /// failure can re-fire it.
    private enum LastOp {
        case summarize
        case breakdown
        case chat(history: [ChatMessage], userMessage: String)
    }
    @State private var lastOp: LastOp?

    private var session: Session? { store.session(id: sessionID) }

    var body: some View {
        if let s = session {
            sessionContent(s)
                .navigationTitle(navigationTitle(for: s))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent(s) }
                .sheet(item: Binding(
                    get: { pendingExport.map { ExportSheetItem(bundle: $0) } },
                    set: { pendingExport = $0?.bundle }
                )) { item in
                    DocumentExporter(urls: item.bundle.shareURLs) { _ in
                        pendingExport = nil
                    }
                    .ignoresSafeArea()
                }
                .fullScreenCover(isPresented: $showZoom) {
                    if let img = UIImage(contentsOfFile: store.imageURL(for: s).path) {
                        ImageZoomView(image: img)
                    }
                }
        } else {
            ContentUnavailableView(
                "Session not found",
                systemImage: "exclamationmark.triangle",
                description: Text("It may have been deleted from history.")
            )
        }
    }

    @ViewBuilder
    private func sessionContent(_ s: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                screenshotImage(s)
                summarySection(s)
                breakdownSection(s)
                chatHistorySection(s)
            }
            .padding()
            // Reserve room at the bottom so the pinned composer doesn't
            // overlap the last chat message.
            .padding(.bottom, 80)
        }
        .onAppear { startSummaryIfNeeded(s) }
        .onDisappear { generationTask?.cancel() }
        .safeAreaInset(edge: .bottom) {
            chatComposer
        }
    }

    /// Wraps the bundle so SwiftUI's `sheet(item:)` can drive the
    /// picker — `ExportBundle` itself isn't `Identifiable`.
    private struct ExportSheetItem: Identifiable {
        let id = UUID()
        let bundle: ExportBundle
    }

    // MARK: - Navigation title

    /// Title is the session date by default, or the first words of
    /// the summary once the model has produced one. Keeps the bar
    /// useful when navigating between multiple sessions via History.
    private func navigationTitle(for s: Session) -> String {
        let summary = streamingSummary.isEmpty ? s.summary : streamingSummary
        if let snippet = summarySnippet(summary), !snippet.isEmpty {
            return snippet
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: s.createdAt)
    }

    /// Strip markdown markers and pull the first ~6 words for the
    /// title. Mirrors the slug logic but lighter — we just want
    /// something readable.
    private func summarySnippet(_ summary: String) -> String? {
        let stripped = summary
            .replacingOccurrences(
                of: #"[*_`#\[\]()<>]"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*TL\s*;\s*DR\s*[:：]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        let words = stripped
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(6)
            .joined(separator: " ")
        return String(words.prefix(48))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ s: Session) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // Show only one trailing action at a time — Cancel
            // dominates while the model is busy, otherwise the export
            // affordance shows once we have something exportable.
            if case .generating = runner.state {
                Button(role: .destructive) { cancel() } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            } else if !s.summary.isEmpty || !streamingSummary.isEmpty {
                exportToolbarButton(s)
            }
        }
    }

    private func exportToolbarButton(_ s: Session) -> some View {
        Button {
            let imageURL = store.imageURL(for: s)
            pendingExport = try? MarkdownExport.stageSession(
                s, sourceImageURL: imageURL
            )
        } label: {
            Label("Export to Obsidian", systemImage: "square.and.arrow.down")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func screenshotImage(_ s: Session) -> some View {
        if let uiImage = UIImage(contentsOfFile: store.imageURL(for: s).path) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showZoom = true
            } label: {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open screenshot full screen")
        }
    }

    @ViewBuilder
    private func summarySection(_ s: Session) -> some View {
        let displayed = streamingSummary.isEmpty ? s.summary : streamingSummary
        let hasText = !displayed.isEmpty
        let hasPersistedSummary = !s.summary.isEmpty

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Summary").font(.title2.weight(.semibold))
                Spacer()
                if hasPersistedSummary, !isBusy {
                    Menu {
                        Button {
                            startSummarize(s)
                        } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Summary actions")
                }
            }
            statusLine
            if hasText {
                MarkdownView(text: displayed)
            }
        }
    }

    @ViewBuilder
    private func breakdownSection(_ s: Session) -> some View {
        let hasSummary = !s.summary.isEmpty || !streamingSummary.isEmpty
        let hasPersistedBreakdown = s.breakdown != nil
        let hasBreakdownText = hasPersistedBreakdown || !streamingBreakdown.isEmpty

        if hasSummary {
            if hasBreakdownText {
                let displayed = streamingBreakdown.isEmpty ? (s.breakdown ?? "") : streamingBreakdown
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Breakdown").font(.title2.weight(.semibold))
                        Spacer()
                        if hasPersistedBreakdown, !isBusy {
                            Menu {
                                Button {
                                    startBreakdown()
                                } label: {
                                    Label("Regenerate", systemImage: "arrow.clockwise")
                                }
                                Button(role: .destructive) {
                                    store.update(id: sessionID) { $0.breakdown = nil }
                                } label: {
                                    Label("Delete breakdown", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Breakdown actions")
                        }
                    }
                    if !displayed.isEmpty {
                        MarkdownView(text: displayed)
                    }
                }
            } else {
                Button {
                    startBreakdown()
                } label: {
                    Label("Generate study breakdown", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
        }
    }

    @ViewBuilder
    private func chatHistorySection(_ s: Session) -> some View {
        if !s.chat.isEmpty || streamingChatMessageID != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Follow-up").font(.title2.weight(.semibold))

                ForEach(s.chat) { message in
                    chatBubble(role: message.role, text: streamingChatBody(for: message))
                }

                // The currently-streaming assistant turn isn't in the
                // store yet (we add it on completion), so render it as a
                // sibling bubble during generation.
                if streamingChatMessageID != nil, !streamingChat.isEmpty {
                    chatBubble(role: .assistant, text: streamingChat)
                }
            }
        }
    }

    /// iMessage-inspired bubbles: user turns are accent-tinted and
    /// right-aligned, assistant turns are surface-tinted and
    /// left-aligned. The role label was the only differentiator
    /// before — alignment + tint is much more legible at a glance.
    @ViewBuilder
    private func chatBubble(role: ChatRole, text: String) -> some View {
        HStack {
            if role == .user { Spacer(minLength: 32) }

            VStack(alignment: .leading, spacing: 4) {
                MarkdownView(text: text)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                role == .user
                    ? Color.accentColor.opacity(0.12)
                    : Color(.secondarySystemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if role == .assistant { Spacer(minLength: 32) }
        }
    }

    /// Pinned at the bottom via `.safeAreaInset(edge: .bottom)`. Has
    /// its own translucent material background so content peeks
    /// through on scroll without making the input unreadable.
    private var chatComposer: some View {
        HStack(spacing: 10) {
            TextField("Ask a follow-up about this screenshot…", text: $chatInput, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit(submitChat)
                .disabled(isBusy && streamingChatMessageID == nil)
            Button {
                submitChat()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(
                isBusy
                || chatInput.trimmingCharacters(in: .whitespaces).isEmpty
                || session?.summary.isEmpty == true
            )
            .accessibilityLabel("Send follow-up")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runner.state {
        case .loading(let p):
            // Fixed-height container so the panel doesn't reflow as
            // the progress bar comes and goes during model load.
            VStack(alignment: .leading, spacing: 4) {
                Text("Loading model… \(Int(p * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: p)
            }
            .frame(height: 36, alignment: .center)
        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Thinking…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let msg):
            HStack(spacing: 10) {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Spacer()
                if lastOp != nil {
                    Button {
                        retryLastOp()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        default:
            EmptyView()
        }
    }

    private var isBusy: Bool {
        switch runner.state {
        case .generating, .loading: return true
        default: return false
        }
    }

    // MARK: - Operations

    private func startSummaryIfNeeded(_ s: Session) {
        guard !summaryStarted else { return }
        summaryStarted = true
        guard s.summary.isEmpty else { return }
        startSummarize(s)
    }

    private func startSummarize(_ s: Session) {
        let imageURL = store.imageURL(for: s)
        let lang = settings.lang
        streamingSummary = ""
        lastOp = .summarize
        runStream(
            chat: [.user(Prompts.summarize(lang: lang), images: [.url(imageURL)])],
            maxTokens: 512,
            onChunk: { chunk in streamingSummary += chunk },
            onDone: {
                store.update(id: sessionID) { $0.summary = streamingSummary }
                streamingSummary = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        )
    }

    private func startBreakdown() {
        guard let s = session else { return }
        let imageURL = store.imageURL(for: s)
        let lang = settings.lang
        let summary = s.summary
        streamingBreakdown = ""
        lastOp = .breakdown
        runStream(
            chat: [.user(
                Prompts.breakdown(lang: lang, summary: summary),
                images: [.url(imageURL)]
            )],
            maxTokens: 768,
            onChunk: { chunk in streamingBreakdown += chunk },
            onDone: {
                store.update(id: sessionID) { $0.breakdown = streamingBreakdown }
                streamingBreakdown = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        )
    }

    private func submitChat() {
        let trimmed = chatInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let s = session else { return }
        chatInput = ""

        // Persist the user turn immediately so it's visible in the
        // chat scroll while the model thinks.
        store.appendChat(id: sessionID, role: .user, text: trimmed)

        let snapshot = store.session(id: sessionID) ?? s
        let history = Array(snapshot.chat.dropLast())  // excludes the user turn we just appended
        startChat(history: history, userMessage: trimmed, on: snapshot)
    }

    private func startChat(history: [ChatMessage], userMessage: String, on s: Session) {
        let imageURL = store.imageURL(for: s)
        let lang = settings.lang
        let summary = s.summary
        let messages = composeChatMessages(
            imageURL: imageURL,
            summary: summary,
            history: history,
            userMessage: userMessage,
            lang: lang
        )

        streamingChat = ""
        let placeholderID = UUID()
        streamingChatMessageID = placeholderID
        lastOp = .chat(history: history, userMessage: userMessage)

        runStream(
            chat: messages,
            maxTokens: 512,
            onChunk: { chunk in streamingChat += chunk },
            onDone: {
                store.update(id: sessionID) { session in
                    session.chat.append(
                        ChatMessage(id: placeholderID, role: .assistant, text: streamingChat)
                    )
                }
                streamingChat = ""
                streamingChatMessageID = nil
            }
        )
    }

    private func retryLastOp() {
        guard let op = lastOp, let s = session else { return }
        switch op {
        case .summarize:
            startSummarize(s)
        case .breakdown:
            startBreakdown()
        case .chat(let history, let userMessage):
            startChat(history: history, userMessage: userMessage, on: s)
        }
    }

    /// Web-app parity: the system prompt (reads "your earlier summary
    /// is …") is concatenated onto the first user turn so the image
    /// stays attached to a single message, matching `js/worker.js`.
    private func composeChatMessages(
        imageURL: URL,
        summary: String,
        history: [ChatMessage],
        userMessage: String,
        lang: Lang
    ) -> [Chat.Message] {
        var out: [Chat.Message] = []
        let allHistory = history + [ChatMessage(role: .user, text: userMessage)]
        let sys = Prompts.chatSystem(lang: lang, summary: summary)
        var firstUserSent = false

        for turn in allHistory {
            switch turn.role {
            case .user where !firstUserSent:
                out.append(.user(
                    sys + "\n\n" + turn.text.trimmingCharacters(in: .whitespaces),
                    images: [.url(imageURL)]
                ))
                firstUserSent = true
            case .user:
                out.append(.user(turn.text.trimmingCharacters(in: .whitespaces)))
            case .assistant:
                out.append(.assistant(turn.text.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    /// Common scaffold for summarize/breakdown/chat: ensure model
    /// loaded, run the stream, route chunks/done/error.
    private func runStream(
        chat: [Chat.Message],
        maxTokens: Int,
        onChunk: @MainActor @escaping (String) -> Void,
        onDone: @MainActor @escaping () -> Void
    ) {
        generationTask?.cancel()
        generationTask = Task { @MainActor in
            await runner.loadModel()
            guard case .ready = runner.state else { return }
            let stream = runner.generate(chat: chat, maxTokens: maxTokens)
            do {
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    onChunk(chunk)
                }
                if !Task.isCancelled { onDone() }
            } catch {
                // runner.state will already reflect the failure
            }
        }
    }

    private func cancel() {
        generationTask?.cancel()
        generationTask = nil
        // Drop in-flight buffers without persisting partial output.
        streamingSummary = ""
        streamingBreakdown = ""
        streamingChat = ""
        streamingChatMessageID = nil
    }

    /// Fetch the persisted body for a chat message — during
    /// generation the streamed assistant message isn't in the
    /// store yet, so we render it from the streaming buffer instead.
    private func streamingChatBody(for message: ChatMessage) -> String {
        if message.id == streamingChatMessageID { return streamingChat }
        return message.text
    }
}
