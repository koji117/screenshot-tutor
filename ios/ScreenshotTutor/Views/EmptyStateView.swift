// EmptyStateView.swift
// Initial screen — pick a screenshot, choose a model, optionally
// pre-load the model so the first generate isn't blocked on a
// multi-minute weight download. Also exposes a "Delete download"
// affordance so users can free disk space without leaving the app.

import SwiftUI
import UIKit

struct EmptyStateView: View {
    @EnvironmentObject var runner: VLMRunner
    @Binding var pickedImage: UIImage?

    // Re-read on every pickerSelection change so the disk-size /
    // downloaded-state below stay accurate without an explicit observer.
    @State private var diskSizeBytes: Int64 = 0
    @State private var isDownloaded: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showCamera: Bool = false
    @State private var pasteFailed: Bool = false
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

    /// Prominent CTA shown above the input buttons when there's an
    /// image waiting in the clipboard. Uses
    /// `UIPasteboard.general.hasImages`, which is a metadata-only
    /// check on iOS 16+ and doesn't trigger the pasteboard banner.
    /// Tapping reads the image and the parent flows it into a session.
    private var clipboardBanner: some View {
        Button(action: pasteFromClipboard) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image ready in clipboard")
                        .font(.headline)
                    Text("Tap to summarize it")
                        .font(.footnote)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.7)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func refreshClipboardState() {
        clipboardHasImage = UIPasteboard.general.hasImages
    }

    /// Three input affordances: Photos library pick, fresh camera
    /// capture, and paste-from-clipboard. The Photos picker is the
    /// existing SwiftUI `PhotosPicker` wrapper; the camera button
    /// presents a `UIImagePickerController` via `CameraPicker`;
    /// paste pulls a UIImage out of `UIPasteboard.general` so the
    /// "Copy and Delete" path on the iPad screenshot thumbnail
    /// flows straight into a session.
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

            Button {
                pasteFromClipboard()
            } label: {
                Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .alert(
            "No image in clipboard",
            isPresented: $pasteFailed
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Take a screenshot, tap the corner thumbnail → Done → Copy and Delete, then come back and tap Paste again.")
        }
    }

    /// Pull a UIImage out of the system pasteboard and feed it through
    /// the same `pickedImage` binding the Photos / Camera paths use.
    /// Triggers iOS's standard "ScreenshotTutor pasted from another
    /// app" banner — that's the system-mandated banner for explicit
    /// pasteboard reads, not anything we can suppress.
    private func pasteFromClipboard() {
        if let image = UIPasteboard.general.image {
            pickedImage = image
        } else {
            pasteFailed = true
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
