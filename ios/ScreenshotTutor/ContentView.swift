// ContentView.swift
// Top-level view. Uses NavigationSplitView so the History sidebar
// is permanently visible alongside the active session on iPad
// regular widths — the platform's native pattern for archive-
// style apps. In compact widths (iPhone, narrow Slide Over),
// NavigationSplitView auto-collapses to a single column with the
// sidebar accessible via a system toolbar toggle.
//
// Routing model is unchanged: a single `route: AppRoute` drives
// what shows in the detail column. The sidebar's NavigationLinks
// set this binding via List(selection:).

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
    @State private var showSettings: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistorySidebar(route: $route)
        } detail: {
            NavigationStack {
                detailContent
                    .toolbar { detailToolbar }
            }
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
    private var detailContent: some View {
        switch route {
        case .empty:
            EmptyStateView(
                pickedImage: $pickedImage,
                onUseFullImage: useFullImage(_:)
            )
            .navigationTitle("Screenshot Tutor")
            .navigationBarTitleDisplayMode(.inline)
        case .session(let id):
            SessionView(sessionID: id)
        case .synthesis:
            SynthesisView(onAfterClear: {
                // After "archive past sessions", history is empty —
                // jump back to the start screen.
                route = .empty
            })
            .navigationTitle("Synthesis")
            .navigationBarTitleDisplayMode(.inline)
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

    /// Toolbar attached to the detail column. Settings opens a
    /// sheet (preferences live there now); New jumps the route
    /// back to the empty state. The History toolbar item is gone —
    /// the sidebar is always accessible.
    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                route = .empty
                pickedImage = nil
            } label: {
                Label("New", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}
