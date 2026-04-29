// ScreenshotTutorApp.swift
// SwiftUI @main entry. The app stays intentionally thin — the heavy
// lifting (model load, generation) lives in VLMRunner so it can be
// re-used from previews and unit tests.

import SwiftUI

@main
struct ScreenshotTutorApp: App {
    @StateObject private var runner = VLMRunner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runner)
        }
    }
}
