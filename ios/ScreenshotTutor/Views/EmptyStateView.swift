// EmptyStateView.swift
// Initial screen — pick a screenshot, choose a model, optionally
// pre-load the model so the first generate isn't blocked on a
// multi-minute weight download.
//
// Layout (top to bottom):
//   • Subtitle hint.
//   • Clipboard banner (only when an image is detected). Two
//     PasteButton actions: crop a region, or use the full image.
//   • Input row: Photos picker, Camera (when available), and two
//     paste rows. All four affordances use the bordered button
//     style so the visual hierarchy is consistent — the banner is
//     the only prominent element when it's present.
//   • Model panel: collapsed to a single status row when the model
//     is ready (with a Menu for switching / deleting), or expanded
//     to the full picker + load + progress when it's not.

import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct EmptyStateView: View {
    @EnvironmentObject var runner: VLMRunner
    @Binding var pickedImage: UIImage?

    /// Skip the region selector and commit the pasted image directly
    /// as a new session. Wired in by ContentView.
    let onUseFullImage: (UIImage) -> Void

    // Re-read on every pickerSelection change so the disk-size /
    // downloaded-state below stay accurate without an explicit observer.
    @State private var diskSizeBytes: Int64 = 0
    @State private var isDownloaded: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showCamera: Bool = false
    @State private var clipboardHasImage: Bool = false

    /// Whether the model panel is showing its full form. Auto-set
    /// based on load state, but the user can also tap the compact
    /// row to expand it (e.g. to switch models).
    @State private var modelPanelExpanded: Bool = true

    /// Drives the inline `PhotosPicker`. Owning the selection here
    /// (rather than wrapping in a separate component) lets the
    /// picker's button style and label match the other input rows.
    @State private var photosItem: PhotosPickerItem?

    /// Two paths a paste can take. `crop` routes the image through
    /// the region selector (the existing default flow); `full` skips
    /// the selector and commits the whole image as a session.
    private enum PasteMode {
        case crop
        case full
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("On-device summaries. Nothing leaves your iPad.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480, alignment: .leading)

            if clipboardHasImage {
                clipboardBanner
                    .frame(maxWidth: 480)
            }

            inputButtons
                .frame(maxWidth: 480)

            modelPanel
                .frame(maxWidth: 480)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $pickedImage)
                .ignoresSafeArea()
        }
        .padding()
        .onAppear {
            refreshDiskState()
            refreshClipboardState()
            // First impression: panel open if there's setup to do,
            // collapsed if the model is already ready.
            modelPanelExpanded = !isReadyState
        }
        .onChange(of: runner.selectedModelID) { _, _ in
            refreshDiskState()
            // User picked a different model — reopen the panel so
            // they can see the load button / status.
            if !isReadyState { modelPanelExpanded = true }
        }
        .onChange(of: photosItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
        .onChange(of: runner.state) { _, newState in
            switch newState {
            case .ready:
                refreshDiskState()
                modelPanelExpanded = false
            case .idle, .failed:
                refreshDiskState()
            default:
                break
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in refreshClipboardState() }
    }

    // MARK: - Banner

    /// iOS notification-style tinted panel shown when there's an
    /// image waiting in the clipboard. Two PasteButtons inside, one
    /// per paste mode. Detection is `UIPasteboard.general.hasImages`
    /// (metadata only — doesn't trigger the "Allow Paste" prompt).
    private var clipboardBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("Image ready in clipboard")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 12) {
                pasteAction(.crop, caption: "Crop a region")
                pasteAction(.full, caption: "Use full image")
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func pasteAction(_ mode: PasteMode, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PasteButton(supportedContentTypes: [UTType.image]) { providers in
                handlePaste(providers, mode: mode)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Input row

    /// Two always-available input affordances: Photos library pick
    /// and Camera. Paste actions live exclusively in the clipboard
    /// banner above and only appear when there's actually an image
    /// to paste — duplicating them here would mean four "Paste"
    /// buttons on screen at once whenever the clipboard had content,
    /// and two disabled "Paste" buttons whenever it didn't.
    private var inputButtons: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photosItem, matching: .images, photoLibrary: .shared()) {
                Label("Pick a screenshot", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if CameraPicker.isAvailable {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Photo loading

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
            await MainActor.run { pickedImage = ui }
        }
    }

    // MARK: - Paste handling

    private func handlePaste(_ providers: [NSItemProvider], mode: PasteMode) {
        Task {
            for provider in providers {
                guard let utType = provider.registeredTypeIdentifiers
                    .compactMap(UTType.init)
                    .first(where: { $0.conforms(to: .image) })
                else { continue }
                do {
                    let data = try await loadData(from: provider, type: utType)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            switch mode {
                            case .crop: pickedImage = image
                            case .full: onUseFullImage(image)
                            }
                        }
                        return
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "ScreenshotTutorPaste",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Pasteboard returned no data"]
                        )
                    )
                }
            }
        }
    }

    private func refreshClipboardState() {
        clipboardHasImage = UIPasteboard.general.hasImages
    }

    // MARK: - Model panel

    private var isReadyState: Bool {
        if case .ready = runner.state { return true }
        return false
    }

    @ViewBuilder
    private var modelPanel: some View {
        if isReadyState && !modelPanelExpanded {
            compactModelPanel
        } else {
            fullModelPanel
        }
    }

    /// One-row summary shown when the model is ready and the panel
    /// has been collapsed. Combines name, size, and ready state into
    /// a single line; switch / delete live in a Menu on the right.
    private var compactModelPanel: some View {
        let label = ModelCatalog.entry(id: runner.selectedModelID)?.label ?? runner.selectedModelID
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(label)
                .font(.callout.weight(.medium))
            if isDownloaded {
                Text("· \(formatBytes(diskSizeBytes))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    modelPanelExpanded = true
                } label: {
                    Label("Switch model…", systemImage: "arrow.triangle.2.circlepath")
                }
                if isDownloaded {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete download", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Model options")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            "Delete this model from disk?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) { deleteConfirmActions } message: {
            Text("The weights will be re-downloaded from Hugging Face the next time you load this model.")
        }
    }

    /// Full panel shown when the model is loading, idle, failed, or
    /// when the user explicitly tapped "Switch model…" from the
    /// compact form.
    private var fullModelPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Model")
                    .font(.headline)
                Spacer()
                if isReadyState {
                    Button {
                        modelPanelExpanded = false
                    } label: {
                        Image(systemName: "chevron.up")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Collapse model panel")
                }
            }

            Picker("Model", selection: $runner.selectedModelID) {
                ForEach(ModelCatalog.entries) { entry in
                    Text("\(entry.label)  ·  \(formatSize(entry.approxSizeMB))")
                        .tag(entry.id)
                }
            }
            .pickerStyle(.menu)

            if let entry = ModelCatalog.entry(id: runner.selectedModelID) {
                Text(entry.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Fixed-height container so the row doesn't reflow as
            // the load button becomes a progress bar.
            modelStatusRow
                .frame(minHeight: 40)

            if isDownloaded {
                HStack {
                    Text("On disk: \(formatBytes(diskSizeBytes))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete download", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            "Delete this model from disk?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) { deleteConfirmActions } message: {
            Text("The weights will be re-downloaded from Hugging Face the next time you load this model.")
        }
    }

    @ViewBuilder
    private var deleteConfirmActions: some View {
        Button("Delete \(formatBytes(diskSizeBytes))", role: .destructive) {
            Task {
                await runner.deleteModel(id: runner.selectedModelID)
                refreshDiskState()
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var modelStatusRow: some View {
        switch runner.state {
        case .ready:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Model ready")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        case .loading(let p):
            VStack(alignment: .leading, spacing: 4) {
                Text("Loading… \(Int(p * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView(value: p)
            }
        case .failed(let msg):
            HStack(spacing: 8) {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button {
                    Task { await runner.loadModel() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        default:
            HStack {
                Button {
                    Task { await runner.loadModel() }
                } label: {
                    Label("Load model", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
    }

    private func refreshDiskState() {
        let id = runner.selectedModelID
        isDownloaded = runner.isDownloaded(id: id)
        diskSizeBytes = runner.diskSize(forID: id)
    }

    private func formatSize(_ mb: Int) -> String {
        if mb >= 1000 {
            let gb = Double(mb) / 1000
            return String(format: gb.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fGB" : "%.1fGB", gb)
        }
        return "\(mb)MB"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
