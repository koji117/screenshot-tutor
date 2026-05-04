// ContentView.swift
// Top-level view. Routes between the three screens that make up the
// app — empty state (pick + load), an active session (summary +
// breakdown + chat), and a synthesis (themes across past sessions).
// Toolbar exposes New, History (sheet), and Language (menu).

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

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(
                onSelect: { id in route = .session(id) },
                onSynthesize: { route = .synthesis }
            )
        }
        .fullScreenCover(item: $pendingImage) { pending in
            RegionSelectorView(
                image: pending.image,
                onConfirm: { final in
                    pendingImage = nil
                    if let session = store.add(image: final) {
                        route = .session(session.id)
                    }
                },
                onCancel: { pendingImage = nil }
            )
        }
        .onChange(of: pickedImage) { _, newImage in
            // The empty state binds to `pickedImage`; when the user
            // picks one, route through the region selector before
            // committing it as a session. iPadOS doesn't expose
            // partial-screen screenshots, so this is where the
            // user trims the screenshot down to the relevant area.
            guard let img = newImage else { return }
            pickedImage = nil
            pendingImage = PendingImage(image: img)
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
        case .session(let id):
            SessionView(sessionID: id)
        case .synthesis:
            SynthesisView(onAfterClear: {
                // After "archive past sessions", history is empty —
                // jump back to the start screen.
                route = .empty
            })
        }
    }

    /// "Use as-is" path — skip the region selector entirely and
    /// commit the image directly to a new session. Photos / camera /
    /// "paste & crop" still go through `pickedImage` and the
    /// `RegionSelectorView` cover above.
    private func useFullImage(_ image: UIImage) {
        if let session = store.add(image: image) {
            route = .session(session.id)
        }
    }

    private var navigationTitle: String {
        switch route {
        case .empty: return "Screenshot Tutor"
        case .session: return "Session"
        case .synthesis: return "Synthesis"
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
            Menu {
                Picker("Language", selection: $settings.lang) {
                    ForEach(Lang.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } label: {
                Label("Language: \(settings.lang.displayName)", systemImage: "globe")
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
