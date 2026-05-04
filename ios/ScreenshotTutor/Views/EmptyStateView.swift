// EmptyStateView.swift
// Initial screen — pick a screenshot, choose a model, optionally
// pre-load the model so the first generate isn't blocked on a
// multi-minute weight download. Also exposes a "Delete download"
// affordance so users can free disk space without leaving the app.

import SwiftUI
import UIKit
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

    /// Two paths a paste can take. `crop` routes the image through
    /// the region selector (the existing default flow); `full` skips
    /// the selector and commits the whole image as a session.
    private enum PasteMode {
        case crop
        case full
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Screenshot Tutor")
                .font(.largeTitle.weight(.semibold))

            Text("Pick or capture an image. The model summarizes it on-device — nothing leaves your iPad.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // When the user just took a screenshot and routed it to
            // the clipboard (via Shortcut or "Copy and Delete"), this
            // banner makes the next step a single tap.
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
        }
        .onChange(of: runner.selectedModelID) { _, _ in refreshDiskState() }
        .onChange(of: runner.state) { _, newState in
            // After a load completes the cache is freshly populated;
            // after delete the directory is gone. Either way, re-read.
            switch newState {
            case .ready, .idle, .failed: refreshDiskState()
            default: break
            }
        }
        // Re-check the clipboard whenever the app comes back to the
        // foreground — the user has likely just taken a screenshot
        // and switched apps, so the clipboard may have an image now
        // that wasn't there at first onAppear.
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in refreshClipboardState() }
    }

    /// Prominent banner shown when there's an image waiting in the
    /// clipboard. The detection uses `UIPasteboard.general.hasImages`,
    /// a metadata-only check that does not trigger the "Allow Paste"
    /// prompt. The actual paste actions are system `PasteButton`s —
    /// the iOS-vetted control that bypasses the prompt because Apple
    /// treats an explicit tap on it as user authorization.
    ///
    /// Two buttons, one per paste mode: "crop" routes through the
    /// region selector (default for screenshots that have UI chrome
    /// to trim), "full" commits the entire image as-is (right when
    /// the screenshot is already exactly what the user wants).
    private var clipboardBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image ready in clipboard")
                        .font(.headline)
                    Text("Choose how to bring it in")
                        .font(.footnote)
                        .opacity(0.85)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                pasteAction(.crop, caption: "Crop a region")
                pasteAction(.full, caption: "Use full image")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// One paste affordance: a system `PasteButton` next to a small
    /// caption explaining the mode. The PasteButton itself always
    /// reads "Paste" (its label is system-controlled), so the
    /// caption is what disambiguates the two side-by-side buttons.
    @ViewBuilder
    private func pasteAction(_ mode: PasteMode, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PasteButton(supportedContentTypes: [UTType.image]) { providers in
                handlePaste(providers, mode: mode)
            }
            .tint(.white)
            Text(caption)
                .font(.caption2)
                .opacity(0.85)
        }
    }

    private func refreshClipboardState() {
        clipboardHasImage = UIPasteboard.general.hasImages
    }

    /// Pull the first UIImage out of the picked NSItemProviders and
    /// feed it through `pickedImage`.
    ///
    /// Two iOS gotchas this avoids:
    ///
    /// 1. `canLoadObject(ofClass:)` queries pasteboard metadata as a
    ///    *separate* pasteboard operation — on iOS 17+ this can be
    ///    refused with `PBErrorDomain Code=13 "Operation not
    ///    authorized."` even immediately after a PasteButton tap.
    ///    Skip the pre-check; just attempt the load.
    ///
    /// 2. The completion-handler form of `loadObject` fires on a
    ///    background queue *after* the PasteButton authorization
    ///    window has closed, which produces the same Code=13 error.
    ///    Use the iOS 16+ async `loadDataRepresentation(forTypeIdentifier:)`
    ///    inside a Task instead — that holds the auth open for the
    ///    duration of the awaited call.
    private func handlePaste(_ providers: [NSItemProvider], mode: PasteMode) {
        Task {
            for provider in providers {
                guard let utType = provider.registeredTypeIdentifiers
                    .compactMap(UTType.init)
                    .first(where: { $0.conforms(to: .image) })
                else { continue }

                do {
                    // NSItemProvider only exposes the completion-handler
                    // form of loadDataRepresentation publicly; wrap it in
                    // a continuation so we can `await` inside the Task
                    // and keep PasteButton's authorization window open
                    // for the duration of the call.
                    let data = try await loadData(from: provider, type: utType)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
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

    /// Four input affordances: Photos library pick, fresh camera
    /// capture, and two system `PasteButton`s — one that crops a
    /// region after pasting (the default for screenshots that have
    /// status bars, app chrome, or surrounding context to trim), and
    /// one that uses the full pasted image as-is.
    ///
    /// Both PasteButtons skip the "Allow Paste" prompt because they
    /// are system-vetted controls; iOS treats their explicit tap as
    /// user authorization the same way it treats Cmd+V from a
    /// hardware keyboard.
    ///
    /// Camera is hidden on environments without a camera (Simulator).
    private var inputButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ImagePickerButton(image: $pickedImage, label: "Pick a screenshot")
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            // Two paste paths, each with a one-line caption that
            // distinguishes them (the PasteButton's label is
            // system-controlled and always reads "Paste").
            pasteRow(.crop, caption: "Paste, then crop a region")
            pasteRow(.full, caption: "Paste the full image as-is")
        }
    }

    @ViewBuilder
    private func pasteRow(_ mode: PasteMode, caption: String) -> some View {
        HStack(spacing: 12) {
            PasteButton(supportedContentTypes: [UTType.image]) { providers in
                handlePaste(providers, mode: mode)
            }
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model")
                .font(.headline)

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

            HStack {
                loadButton
                statusLabel
                Spacer()
            }

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
                            .font(.footnote)
                    }
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
        ) {
            Button("Delete \(formatBytes(diskSizeBytes))", role: .destructive) {
                Task {
                    await runner.deleteModel(id: runner.selectedModelID)
                    refreshDiskState()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The weights will be re-downloaded from Hugging Face the next time you load this model.")
        }
    }

    @ViewBuilder
    private var loadButton: some View {
        switch runner.state {
        case .ready:
            Label("Model ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .loading:
            ProgressView()
        default:
            Button("Load model") {
                Task { await runner.loadModel() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch runner.state {
        case .loading(let p):
            Text("\(Int(p * 100))%")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let msg):
            Text(msg)
                .font(.footnote)
                .foregroundStyle(.red)
                .lineLimit(2)
        default:
            EmptyView()
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
