// EmptyStateView.swift
// Initial screen — pick a screenshot, choose a model, optionally
// pre-load the model so the first generate isn't blocked on a
// multi-minute weight download.

import SwiftUI
import UIKit

struct EmptyStateView: View {
    @EnvironmentObject var runner: VLMRunner
    @Binding var pickedImage: UIImage?

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
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model")
                .font(.headline)

            Picker("Model", selection: $runner.selectedModelID) {
                ForEach(ModelCatalog.entries) { entry in
                    Text("\(entry.label)  ·  \(formatSize(entry.approxSizeMB))")
                        .tag(entry.huggingFaceID)
                }
            }
            .pickerStyle(.menu)

            if let entry = ModelCatalog.entries.first(where: { $0.huggingFaceID == runner.selectedModelID }) {
                Text(entry.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                loadButton
                statusLabel
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    private func formatSize(_ mb: Int) -> String {
        if mb >= 1000 {
            let gb = Double(mb) / 1000
            return String(format: gb.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fGB" : "%.1fGB", gb)
        }
        return "\(mb)MB"
    }
}
