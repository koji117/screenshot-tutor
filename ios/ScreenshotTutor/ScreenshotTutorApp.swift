// ScreenshotTutorApp.swift
// SwiftUI @main entry. The app stays intentionally thin — the heavy
// lifting (model load, generation, session persistence, language
// preference) lives in the @MainActor stores below so they can be
// shared across view hierarchies and survive view recomposition.

import SwiftUI

@main
struct ScreenshotTutorApp: App {
    @StateObject private var runner = VLMRunner()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runner)
                .environmentObject(sessionStore)
                .environmentObject(settings)
        }
    }
}
