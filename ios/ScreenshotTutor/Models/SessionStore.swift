// SessionStore.swift
// JSON-on-disk persistence for `Session` records, mirroring the web
// app's localStorage store but with JPEG files on the file system
// instead of inline data URLs.
//
// Layout under <Application Support>:
//   sessions.json        — array of Session, newest first
//   images/<uuid>.jpg    — main image (resized to 1280px max edge)
//   thumbs/<uuid>.jpg    — history-list thumbnail (240px max edge)

import Foundation
import UIKit

@MainActor
final class SessionStore: ObservableObject {

    /// Maximum number of sessions kept on disk. Older ones are evicted
    /// (file + JSON entry) when this is exceeded — same cap as the web
    /// app, to keep the history list scannable.
    static let limit: Int = 20

    @Published private(set) var sessions: [Session] = []

    private let imagesDir: URL
    private let thumbsDir: URL
    private let sessionsFile: URL

    init() {
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory

        self.imagesDir = support.appendingPathComponent("images", isDirectory: true)
        self.thumbsDir = support.appendingPathComponent("thumbs", isDirectory: true)
        self.sessionsFile = support.appendingPathComponent("sessions.json")

        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)

        load()
    }

    // MARK: - URL accessors

    func imageURL(for session: Session) -> URL {
        imagesDir.appendingPathComponent(session.imagePath)
    }
    func thumbURL(for session: Session) -> URL {
        thumbsDir.appendingPathComponent(session.thumbPath)
    }

    // MARK: - Lookup

    func session(id: UUID) -> Session? {
        sessions.first(where: { $0.id == id })
    }

    // MARK: - Mutations

    /// Create a new session backed by a freshly-resized JPEG on disk.
    /// Returns nil if the image can't be encoded.
    @discardableResult
    func add(image: UIImage) -> Session? {
        let id = UUID()
        let imageName = "\(id.uuidString).jpg"
        let thumbName = "\(id.uuidString)-thumb.jpg"

        guard let mainData = resized(image, maxEdge: 1280, quality: 0.85),
              let thumbData = resized(image, maxEdge: 240, quality: 0.85)
        else { return nil }

        let imageURL = imagesDir.appendingPathComponent(imageName)
        let thumbURL = thumbsDir.appendingPathComponent(thumbName)
        do {
            try mainData.write(to: imageURL)
            try thumbData.write(to: thumbURL)
        } catch {
            return nil
        }

        let session = Session(
            id: id,
            createdAt: Date(),
            imagePath: imageName,
            thumbPath: thumbName
        )
        sessions.insert(session, at: 0)
        trimAndPersist()
        return session
    }

    /// Mutate a session by id and persist. Silently no-ops if the
    /// session was deleted in the meantime.
    func update(id: UUID, mutate: (inout Session) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sessions[idx])
        save()
    }

    /// Append a chat turn. Convenience over `update`.
    func appendChat(id: UUID, role: ChatRole, text: String) {
        update(id: id) { session in
            session.chat.append(ChatMessage(role: role, text: text))
        }
    }

    /// Remove a session and its on-disk files.
    func delete(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let removed = sessions.remove(at: idx)
        try? FileManager.default.removeItem(at: imageURL(for: removed))
        try? FileManager.default.removeItem(at: thumbURL(for: removed))
        save()
    }

    /// Remove every session record + image. Used by the synthesis
    /// view's "archive after synthesize" flow.
    func clearAll() {
        for session in sessions {
            try? FileManager.default.removeItem(at: imageURL(for: session))
            try? FileManager.default.removeItem(at: thumbURL(for: session))
        }
        sessions.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: sessionsFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Session].self, from: data) {
            sessions = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sessions) {
            try? data.write(to: sessionsFile, options: .atomic)
        }
    }

    private func trimAndPersist() {
        while sessions.count > Self.limit {
            let removed = sessions.removeLast()
            try? FileManager.default.removeItem(at: imageURL(for: removed))
            try? FileManager.default.removeItem(at: thumbURL(for: removed))
        }
        save()
    }

    // MARK: - Image resizing helper

    private func resized(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1.0
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
