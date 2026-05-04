// Mascot.swift
// State-aware glyphs for the app's monkey character. The hero on
// the empty state and the small variants in HistorySidebar /
// SynthesisView's empty messaging all consume `MascotState` so
// the character speaks with one voice across the app.
//
// Implementation is composed system emoji rather than a custom
// asset — adapts to Dynamic Type for free, and any swap to a real
// illustrated mascot later only needs to update the rendering, not
// the state mapping.

import Foundation

struct MascotState {
    /// The primary monkey glyph (always present).
    let primary: String
    /// Optional secondary prop (camera, thought bubble, etc.) —
    /// nil for states where the monkey stands alone.
    let secondary: String?
    /// VoiceOver label describing what the mascot is conveying.
    let accessibilityLabel: String

    // MARK: - Presets

    /// Default — at rest with the camera, ready to receive a
    /// screenshot.
    static let idle = MascotState(
        primary: "🐵",
        secondary: "📷",
        accessibilityLabel: "Screenshot Tutor — a monkey with a camera"
    )

    /// Model is downloading or loading into memory. Patient pose.
    static let waiting = MascotState(
        primary: "🐵",
        secondary: "💭",
        accessibilityLabel: "Screenshot Tutor — waiting"
    )

    /// Model is generating output for a specific session. Reading
    /// the screenshot.
    static let reading = MascotState(
        primary: "🐵",
        secondary: "📖",
        accessibilityLabel: "Screenshot Tutor — reading"
    )

    /// Something went wrong. The "see no evil" monkey reads as
    /// "let's not look at that" without escalating to alarm.
    static let stumped = MascotState(
        primary: "🙈",
        secondary: nil,
        accessibilityLabel: "Screenshot Tutor — something went wrong"
    )

    /// Empty / waiting-for-content state. The monkey stands alone
    /// without the camera prop, hinting "nothing yet."
    static let empty = MascotState(
        primary: "🐵",
        secondary: nil,
        accessibilityLabel: "Screenshot Tutor"
    )

    /// Used by Synthesis when there aren't enough sessions yet —
    /// thoughtful pose.
    static let pondering = MascotState(
        primary: "🐵",
        secondary: "🤔",
        accessibilityLabel: "Screenshot Tutor — pondering"
    )

    /// Session not found / lost.
    static let lost = MascotState(
        primary: "🙉",
        secondary: nil,
        accessibilityLabel: "Screenshot Tutor — couldn't find that"
    )

    // MARK: - State derivation

    /// Map a `VLMRunner.State` to the right mascot pose for the
    /// home hero. Generating maps to `reading` only when the user
    /// is actually on a session; for the home screen we don't see
    /// .generating, but the mapping still makes sense.
    @MainActor
    static func from(_ state: VLMRunner.State) -> MascotState {
        switch state {
        case .loading: return .waiting
        case .generating: return .reading
        case .failed: return .stumped
        case .ready, .idle: return .idle
        }
    }
}
