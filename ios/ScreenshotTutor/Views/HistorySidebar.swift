// HistorySidebar.swift
// Permanent sidebar inside the NavigationSplitView. Replaces the
// previous full-screen History sheet — on iPad regular widths the
// list is always visible alongside the active session, which is
// the platform's native pattern for archive-style apps (Mail,
// Notes, Files, Reminders).
//
// In compact widths (iPhone, narrow Slide Over), NavigationSplitView
// auto-collapses this view into the navigation stack root; the
// detail column pushes onto it and a system-provided sidebar
// toggle in the navigation bar lets the user swap back.

import SwiftUI
import UIKit

struct HistorySidebar: View {
    @Binding var route: AppRoute
    @EnvironmentObject var store: SessionStore

    /// Tracks the row the user has indicated they want to delete,
    /// so we can show the confirmation dialog without losing which
    /// session it was about.
    @State private var pendingDelete: UUID?

    /// `List(selection:)` on iOS requires an `Optional<SelectionValue>`
    /// binding, but the parent owns `route` as a non-optional with
    /// `.empty` as its default. Adapt by wrapping: present route as
    /// optional to the List, and only write back when the user
    /// actually picks a row (ignore the deselect case).
    private var routeSelection: Binding<AppRoute?> {
        Binding(
            get: { route },
            set: { newValue in
                if let newValue { route = newValue }
            }
        )
    }

    var body: some View {
        List(selection: routeSelection) {
            Section {
                NavigationLink(value: AppRoute.empty) {
                    Label("New session", systemImage: "plus.circle")
                }

                if store.sessions.count >= 2 {
                    NavigationLink(value: AppRoute.synthesis) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Synthesize")
                                Text("Themes across past sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                }
            }

            Section("Past sessions") {
                if store.sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: AppRoute.session(session.id)) {
                            row(session)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = session.id
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Screenshot Tutor")
        .confirmationDialog(
            "Delete this screenshot?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete {
                    if case .session(let activeID) = route, activeID == id {
                        // The session being viewed in the detail
                        // column is about to disappear; route back
                        // to the empty state so SessionView doesn't
                        // try to render a missing record.
                        route = .empty
                    }
                    store.delete(id: id)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ session: Session) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let ui = UIImage(contentsOfFile: store.thumbURL(for: session).path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDate(session.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewText(session.summary))
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Strip the model's frequent "TL;DR:" prefix and any markdown
    /// markers so the row reads as content, not as markup.
    private func previewText(_ summary: String) -> String {
        let stripped = summary
            .replacingOccurrences(
                of: #"^\s*\*{0,2}TL\s*;\s*DR\s*\*{0,2}\s*[:：]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"[*_`#\[\]()<>]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "(no summary yet)" : stripped
    }
}
