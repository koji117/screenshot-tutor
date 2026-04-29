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

    var body: some View {
        VStack(spacing: 20) {
            Text("Screenshot Tutor")
                .font(.largeTitle.weight(.semibold))

            Text("Pick a screenshot. The model summarizes it on-device — nothing leaves your iPad.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ImagePickerButton(image: $pickedImage, label: "Pick a screenshot")
                .frame(maxWidth: 360)

            modelPanel
                .frame(maxWidth: 480)
        }
        .padding()
        .onAppear { refreshDiskState() }
        .onChange(of: runner.selectedModelID) { _, _ in refreshDiskState() }
        .onChange(of: runner.state) { _, newState in
            // After a load completes the cache is freshly populated;
            // after delete the directory is gone. Either way, re-read.
            switch newState {
            case .ready, .idle, .failed: refreshDiskState()
            default: break
            }
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
