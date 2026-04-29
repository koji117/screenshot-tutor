// SessionView.swift
// Active session: screenshot + streaming summary, optional study
// breakdown, and a follow-up chat. Equivalent of the web app's
// `js/components/session.js`. State for the summary/breakdown text
// is held locally during streaming and committed back to the
// SessionStore once the model emits its final chunk.

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

    private var session: Session? { store.session(id: sessionID) }

    var body: some View {
        if let s = session {
            sessionContent(s)
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
                chatSection(s)
                if case .generating = runner.state {
                    Button("Cancel", role: .destructive) { cancel() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .onAppear { startSummaryIfNeeded(s) }
        .onDisappear { generationTask?.cancel() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func screenshotImage(_ s: Session) -> some View {
        if let uiImage = UIImage(contentsOfFile: store.imageURL(for: s).path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func summarySection(_ s: Session) -> some View {
        let displayed = streamingSummary.isEmpty ? s.summary : streamingSummary

        VStack(alignment: .leading, spacing: 8) {
            Text("Summary").font(.title2.weight(.semibold))
            statusLine
            if !displayed.isEmpty {
                MarkdownView(text: displayed)
            }
        }
    }

    @ViewBuilder
    private func breakdownSection(_ s: Session) -> some View {
        // Only show breakdown UI once we have a summary.
        let hasSummary = !s.summary.isEmpty || !streamingSummary.isEmpty
        let hasBreakdown = (s.breakdown != nil) || !streamingBreakdown.isEmpty

        if hasSummary {
            if hasBreakdown {
                let displayed = streamingBreakdown.isEmpty ? (s.breakdown ?? "") : streamingBreakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Breakdown").font(.title2.weight(.semibold))
                    if !displayed.isEmpty {
                        MarkdownView(text: displayed)
                    }
                }
            } else {
                Button("Generate study breakdown") { startBreakdown() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            }
        }
    }

    @ViewBuilder
    private func chatSection(_ s: Session) -> some View {
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

            HStack {
                TextField("Ask a follow-up about this screenshot…", text: $chatInput)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(submitChat)
                    .disabled(isBusy)
                Button("Send", action: submitChat)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || chatInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func chatBubble(role: ChatRole, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role == .user ? "You" : "Tutor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            MarkdownView(text: text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(role == .user ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                Text("Thinking…")
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
        runStream(
            chat: [.user(Prompts.summarize(lang: lang), images: [.url(imageURL)])],
            maxTokens: 512,
            onChunk: { chunk in streamingSummary += chunk },
            onDone: {
                store.update(id: sessionID) { $0.summary = streamingSummary }
                streamingSummary = ""
            }
        )
    }

    private func startBreakdown() {
        guard let s = session else { return }
        let imageURL = store.imageURL(for: s)
        let lang = settings.lang
        let summary = s.summary
        streamingBreakdown = ""
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
        let history = Array(snapshot.chat.dropLast())  // excludes the user turn we just appended (it's in `userMessage`)
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
