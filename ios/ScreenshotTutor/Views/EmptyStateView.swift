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

    // Re-read on every pickerSelection change so the disk-size /
    // downloaded-state below stay accurate without an explicit observer.
    @State private var diskSizeBytes: Int64 = 0
    @State private var isDownloaded: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showCamera: Bool = false
    @State private var clipboardHasImage: Bool = false

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
    /// prompt. The actual paste action is a system `PasteButton` —
    /// that's the iOS-vetted control that bypasses the prompt because
    /// Apple treats an explicit tap on it as user authorization.
    private var clipboardBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Image ready in clipboard")
                    .font(.headline)
                Text("Tap Paste to summarize it")
                    .font(.footnote)
                    .opacity(0.85)
            }
            Spacer()
            pasteControl
                .tint(.white)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The system paste button. Auto-disables when the clipboard has
    /// no image-typed item, so it doubles as a "paste is available"
    /// indicator. Crucially, it does NOT trigger the "Allow Paste"
    /// prompt — iOS treats an explicit tap on a `PasteButton` as
    /// authorization, the same way it treats `Cmd+V` from the
    /// hardware keyboard.
    private var pasteControl: some View {
        PasteButton(supportedContentTypes: [UTType.image]) { providers in
            handlePaste(providers)
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
    private func handlePaste(_ providers: [NSItemProvider]) {
        Task {
            for provider in providers {
                guard let typeID = provider.registeredTypeIdentifiers.first(where: { id in
                    guard let utType = UTType(id) else { return false }
                    return utType.conforms(to: .image)
                }) else { continue }

                do {
                    let data = try await provider.loadDataRepresentation(
                        forTypeIdentifier: typeID
                    )
                    if let image = UIImage(data: data) {
                        await MainActor.run { pickedImage = image }
                        return
                    }
                } catch {
                    // Try the next provider; nothing usable on this one.
                    continue
                }
            }
        }
    }

    /// Three input affordances: Photos library pick, fresh camera
    /// capture, and a system `PasteButton`. The PasteButton replaces
    /// the previous custom Button that called `UIPasteboard.general.image`
    /// — that direct pasteboard read triggered the "Allow Paste"
    /// prompt every time, which got intolerable for a screenshot-
    /// heavy workflow. The system PasteButton bypasses that prompt
    /// entirely; iOS treats its explicit tap as authorization.
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

            pasteControl
                .frame(maxWidth: .infinity)
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
