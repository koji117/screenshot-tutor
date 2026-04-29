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

struct ContentView: View {
    @EnvironmentObject var runner: VLMRunner
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var settings: AppSettings

    @State private var route: AppRoute = .empty
    @State private var pickedImage: UIImage?
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
        .onChange(of: pickedImage) { _, newImage in
            // The empty state binds to `pickedImage`; when the user
            // picks one, materialize a session record and navigate.
            guard let img = newImage else { return }
            if let session = store.add(image: img) {
                pickedImage = nil
                route = .session(session.id)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch route {
        case .empty:
            EmptyStateView(pickedImage: $pickedImage)
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
