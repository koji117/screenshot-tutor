// HistoryView.swift
// List of past sessions, presented as a sheet from the toolbar's
// History button. Tap a row to open that session; swipe to delete;
// optional "Synthesize" button at the top kicks off a cross-session
// reflection.

import SwiftUI
import UIKit

struct HistoryView: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) var dismiss

    /// Called with the selected session id; the parent navigates and
    /// dismisses this sheet.
    let onSelect: (UUID) -> Void
    /// Called when the user taps "Synthesize"; parent shows the
    /// synthesis view.
    let onSynthesize: () -> Void

    @State private var pendingDelete: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "No past screenshots yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Pick a screenshot to start.")
                    )
                } else {
                    List {
                        Section {
                            Button {
                                onSynthesize()
                                dismiss()
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text("Synthesize").font(.body.weight(.semibold))
                                        Text("Find themes and gaps across past sessions")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "sparkles")
                                }
                            }
                            .disabled(store.sessions.count < 2)
                        }
                        Section("Past sessions") {
                            ForEach(store.sessions) { session in
                                Button {
                                    onSelect(session.id)
                                    dismiss()
                                } label: {
                                    rowContent(session)
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
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this screenshot?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDelete { store.delete(id: id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ session: Session) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let ui = UIImage(contentsOfFile: store.thumbURL(for: session).path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 60, height: 60)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate(session.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(previewText(session.summary))
                    .font(.subheadline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func previewText(_ summary: String) -> String {
        let stripped = summary
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return "(no summary yet)" }
        return stripped
    }
}
