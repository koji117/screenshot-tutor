// Session.swift
// Native equivalent of the web app's localStorage session record.
// Each Session captures a single screenshot + the model's outputs
// for it (summary, optional breakdown, optional follow-up chat).
//
// Images live as JPEG files in the app's Application Support
// directory rather than inlined as data URLs — iOS gives us real
// disk so there's no point in stuffing 1MB+ images into JSON.

import Foundation

enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: ChatRole
    var text: String
    var ts: Date = Date()
}

struct Session: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    /// Filename within `<AppSupport>/images/`. Resolved via
    /// `SessionStore.imageURL(for:)`.
    var imagePath: String

    /// Filename within `<AppSupport>/thumbs/` (240px max edge).
    var thumbPath: String

    var summary: String = ""

    /// Nil until the user taps "Generate study breakdown".
    var breakdown: String?

    var chat: [ChatMessage] = []
}
