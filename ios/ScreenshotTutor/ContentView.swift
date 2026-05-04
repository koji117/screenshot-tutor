// ContentView.swift
// Top-level view. Routes between the three screens that make up the
// app — empty state (pick + load), an active session (summary +
// breakdown + chat), and a synthesis (themes across past sessions).
// Toolbar exposes History, Settings, and New.

import SwiftUI
import UIKit

enum AppRoute: Hashable {
    case empty
    case session(UUID)
    case synthesis
}

/// Wraps a UIImage with a stable id so SwiftUI's
/// `fullScreenCover(item:)` can drive the region selector. UIImage
/// itself isn't Identifiable.
private struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ContentView: View {
    @EnvironmentObject var runner: VLMRunner
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: AppSettings

    @State private var route: AppRoute = .empty
    @State private var pickedImage: UIImage?
    @State private var pendingImage: PendingImage?
    @State private var showHistory: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationStack {
            mainContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(
                onSelect: { id in route = .session(id) },
                onSynthesize: { route = .synthesis }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $pendingImage) { pending in
            RegionSelectorView(
                image: pending.image,
                onConfirm: { final in
                    pendingImage = nil
                    if let session = store.add(image: final) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        route = .session(session.id)
                    }
                },
                onCancel: { pendingImage = nil }
            )
        }
        .onChange(of: pickedImage) { _, newImage in
            // Route fresh picks through either the region selector
            // or directly to a new session, depending on the user's
            // default-image-mode preference. Paste actions bypass
            // this — they call onUseFullImage / set pickedImage
            // explicitly per their own per-tap choice.
            guard let img = newImage else { return }
            pickedImage = nil
            switch settings.imageMode {
            case .crop:
                pendingImage = PendingImage(image: img)
            case .full:
                useFullImage(img)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch route {
        case .empty:
            EmptyStateView(
                pickedImage: $pickedImage,
                onUseFullImage: useFullImage(_:)
            )
            .navigationTitle("Screenshot Tutor")
        case .session(let id):
            SessionView(sessionID: id)
        case .synthesis:
            SynthesisView(onAfterClear: {
                // After "archive past sessions", history is empty —
                // jump back to the start screen.
                route = .empty
            })
            .navigationTitle("Synthesis")
        }
    }

    /// "Use as-is" path — skip the region selector entirely and
    /// commit the image directly to a new session. Photos / camera
    /// route here when `settings.imageMode == .full`; the paste
    /// "Use full image" button always routes here.
    private func useFullImage(_ image: UIImage) {
        if let session = store.add(image: image) {
            UISelectionFeedbackGenerator().selectionChanged()
            route = .session(session.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                route = .empty
                pickedImage = nil
            } label: {
                Label("New", systemImage: "plus")
            }
        }
    }
}
