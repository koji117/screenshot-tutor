// SettingsView.swift
// In-app settings sheet. Replaces the inline Language Menu that
// used to live in the toolbar — gathering preferences here keeps
// the navigation bar clean (History + Settings + New) and gives
// future per-user options a natural home.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var runner: VLMRunner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Output language", selection: $settings.lang) {
                        ForEach(Lang.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                } header: {
                    Text("Output")
                } footer: {
                    Text("Language the model writes summaries, breakdowns, and synthesis in.")
                }

                Section {
                    Picker("Default mode for new images", selection: $settings.imageMode) {
                        ForEach(ImageMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("Input")
                } footer: {
                    Text("Applies to Photos and Camera picks. Paste has its own per-tap choice and ignores this setting.")
                }

                Section {
                    Picker("Model", selection: $runner.selectedModelID) {
                        ForEach(ModelCatalog.entries) { entry in
                            Text(entry.label).tag(entry.id)
                        }
                    }
                    if let entry = ModelCatalog.entry(id: runner.selectedModelID) {
                        Text(entry.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Switching here changes which model the next session uses. Already-loaded weights stay in memory until you switch back to a different one.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
