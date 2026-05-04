// EmptyStateView.swift
// Initial screen — pick a screenshot, choose a model, optionally
// pre-load the model so the first generate isn't blocked on a
// multi-minute weight download.
//
// Layout (top to bottom):
//   • Clipboard banner (only when an image is detected). Pure
//     signal — points the user at the input row's paste rows,
//     carries no buttons of its own.
//   • Input row: Photos / Camera (top), then two paste rows. The
//     paste rows use system PasteButtons so the iOS "Allow Paste"
//     prompt is bypassed — the captions next to them ("Crop a
//     region" / "Use full image") explain what each does, since
//     PasteButton's own label is system-fixed to "Paste."
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

    /// Tracks whether a drag-and-drop hover is currently over the
    /// view, used to tint the background while a drop is possible.
    @State private var isDropTargeted: Bool = false

    /// Two paths a paste can take. `crop` routes the image through
    /// the region selector (the existing default flow); `full` skips
    /// the selector and commits the whole image as a session.
    private enum PasteMode {
        case crop
        case full
    }

    var body: some View {
        VStack(spacing: 16) {
            // 640pt feels right across the iPad range — narrow
            // enough to read comfortably on iPad mini, wide enough
            // not to look like a phone-content island on a 13"
            // iPad Pro in landscape.
            if clipboardHasImage {
                clipboardBanner
                    .frame(maxWidth: 640)
            }

            inputButtons
                .frame(maxWidth: 640)

            modelPanel
                .frame(maxWidth: 640)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $pickedImage)
                .ignoresSafeArea()
        }
        .padding()
        // System-level drag-and-drop. Drop an image from Files,
        // Safari, Photos, etc. and we route it through the same
        // path as Photos / Camera (respects settings.imageMode for
        // crop vs full).
        .onDrop(
            of: [.image, .png, .jpeg, .heic],
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
        .background(
            // Subtle accent tint while a drag hovers, so the user
            // can see the empty state will accept the drop.
            Color.accentColor.opacity(isDropTargeted ? 0.08 : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        )
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

    /// iOS notification-style tinted hint shown when there's an
    /// image waiting in the clipboard. Carries no PasteButtons of
    /// its own — those live in the input row below and stay
    /// visible regardless of clipboard state. The banner exists
    /// purely as a "your screenshot is ready" cue, pointing the
    /// user's eye at the paste rows.
    ///
    /// Detection is `UIPasteboard.general.hasImages` (metadata-only;
    /// doesn't trigger the "Allow Paste" prompt).
    private var clipboardBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Image ready in clipboard")
                    .font(.headline)
                Text("Tap a Paste option below")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.accentColor.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Input row

    /// Four input affordances. Photos and Camera (top row) are the
    /// always-explicit picks. The two Paste rows below are always
    /// visible — the system PasteButton auto-disables when the
    /// clipboard has no image, which serves as the visual cue.
    /// When the clipboard *does* have an image, the banner above
    /// flags it and the buttons here become enabled.
    private var inputButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Pre-filter to screenshots first, falling back to
                // any image. The Photos app's Screenshots album is
                // where almost every pick will come from, so landing
                // the user there saves a tap.
                PhotosPicker(
                    selection: $photosItem,
                    matching: .any(of: [.screenshots, .images]),
                    photoLibrary: .shared()
                ) {
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

            // Two paste paths via system PasteButtons (which skip
            // the iOS "Allow Paste" prompt). PasteButton's own label
            // is system-fixed to "Paste"; the caption beside it
            // explains what each row will do with the pasted image.
            pasteRow(.crop, caption: "Crop a region")
            pasteRow(.full, caption: "Use full image")
        }
    }

    @ViewBuilder
    private func pasteRow(_ mode: PasteMode, caption: String) -> some View {
        HStack(spacing: 12) {
            PasteButton(supportedContentTypes: [UTType.image]) { providers in
                handlePaste(providers, mode: mode)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
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

    // MARK: - Drag-and-drop

    /// `onDrop` handler. Walks the dropped providers, decodes the
    /// first image-typed payload, and feeds it through `pickedImage`
    /// — ContentView's `onChange` then routes to the region selector
    /// or directly to a session per the user's `imageMode` setting.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
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
                            pickedImage = image
                        }
                        return
                    }
                } catch {
                    continue
                }
            }
        }
        return true
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Model ready")
        case .loading(let p):
            VStack(alignment: .leading, spacing: 4) {
                Text("Loading… \(Int(p * 100))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ProgressView(value: p)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading model")
            .accessibilityValue("\(Int(p * 100)) percent")
            .accessibilityAddTraits(.updatesFrequently)
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

    /// Both helpers route through `ByteCountFormatter` so the size
    /// format stays consistent across the panel — "On disk: 1.5 GB"
    /// uses the same locale-aware rounding as "Gemma 4 E2B (4-bit) ·
    /// 1.5 GB" in the picker. `formatSize` takes the catalog's
    /// approximate-MB value; `formatBytes` takes a real on-disk byte
    /// count from the runner.
    private func formatSize(_ mb: Int) -> String {
        formatBytes(Int64(mb) * 1_000_000)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
