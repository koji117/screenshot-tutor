// MarkdownExport.swift
// Port of the web app's `js/exports.js`. Two responsibilities:
//
//   1. Build the markdown body + Obsidian-style frontmatter for a
//      session or a synthesis (see `sessionMarkdown` /
//      `synthesisMarkdown`).
//   2. Stage the file(s) to a temp directory so they can be handed
//      to a `ShareLink` / `UIActivityViewController` for the user
//      to save into their Obsidian vault on iCloud Drive (or send
//      to Obsidian directly via its share extension).
//
// File naming and frontmatter shape match the web app exactly so
// markdown produced on either device drops into the same vault
// without surprises.

import Foundation
import UIKit

enum MarkdownExport {

    // MARK: - Public: build markdown

    /// Markdown for a single session. Same structure as the web app's
    /// `buildSessionMarkdown`: frontmatter, summary, optional
    /// breakdown, optional chat thread.
    static func sessionMarkdown(_ session: Session) -> String {
        let parts = timestampParts(session.createdAt)
        let fm = frontmatter([
            ("created", parts.iso),
            ("source", "screenshot-tutor"),
            ("tags", ["study", "screenshot"]),
        ])

        var lines: [String] = []
        lines.append("# Screenshot summary")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append(session.summary.isEmpty ? "_(no summary)_" : session.summary)

        if let breakdown = session.breakdown, !breakdown.isEmpty {
            lines.append("")
            lines.append("## Study breakdown")
            lines.append("")
            lines.append(breakdown)
        }

        if !session.chat.isEmpty {
            lines.append("")
            lines.append("## Follow-up")
            lines.append("")
            for m in session.chat {
                let role = (m.role == .user) ? "You" : "Tutor"
                lines.append("**\(role):**")
                lines.append("")
                lines.append(m.text)
                lines.append("")
            }
        }

        return fm + lines.joined(separator: "\n") + "\n"
    }

    /// Markdown for a synthesis. The optional `imageRefs` add a
    /// "Source screenshots" section with `![[wikilinks]]`, matching
    /// the web app's synthesis export when source images are bundled.
    static func synthesisMarkdown(
        text: String,
        sessionCount: Int,
        date: Date = Date(),
        imageRefs: [(filename: String, createdAt: Date)] = []
    ) -> String {
        let parts = timestampParts(date)
        let fm = frontmatter([
            ("created", parts.iso),
            ("source", "screenshot-tutor"),
            ("type", "synthesis"),
            ("sessions", String(sessionCount)),
            ("tags", ["study", "synthesis"]),
        ])

        var lines: [String] = []
        lines.append("# Study synthesis")
        lines.append("")
        lines.append("_Across \(sessionCount) sessions_")
        lines.append("")
        lines.append(text)

        if !imageRefs.isEmpty {
            lines.append("")
            lines.append("---")
            lines.append("")
            lines.append("## Source screenshots")
            lines.append("")
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            for ref in imageRefs {
                lines.append("**\(f.string(from: ref.createdAt))**")
                lines.append("")
                lines.append("![[\(ref.filename)]]")
                lines.append("")
            }
        }

        return fm + lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Public: filenames

    static func sessionFilename(_ session: Session) -> String {
        let parts = timestampParts(session.createdAt)
        let slug = slugify(session.summary)
        let core = slug.isEmpty ? "screenshot" : slug
        return "\(parts.ymd)-\(parts.hm)-\(core).md"
    }

    static func synthesisFilename(date: Date = Date()) -> String {
        let parts = timestampParts(date)
        return "\(parts.ymd)-\(parts.hm)-synthesis.md"
    }

    /// Bundled-image filename for a synthesis source. Uses seconds in
    /// the timestamp + a short id-derived suffix to avoid collisions
    /// when multiple sessions share the same minute.
    static func sourceImageFilename(_ session: Session) -> String {
        let parts = timestampParts(session.createdAt)
        let slug = slugify(session.summary)
        let core = slug.isEmpty ? "screenshot" : slug
        let raw = session.id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        let idTag = String(raw.prefix(6))
        return "\(parts.ymd)-\(parts.hms)-\(core)-\(idTag).jpg"
    }

    // MARK: - Public: stage to temp files for ShareLink

    /// Write `sessionMarkdown(session)` to a fresh temp file and
    /// return the URL. Caller hands this URL to `ShareLink` /
    /// `UIActivityViewController`.
    static func stageSession(_ session: Session) throws -> URL {
        let url = stagingURL(name: sessionFilename(session))
        try sessionMarkdown(session).data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// Write the synthesis markdown plus copies of each session's
    /// JPEG into a fresh temp directory. Returns every URL — pass
    /// the array to `ShareLink(items:)` so they save together when
    /// the user picks "Save to Files" → vault folder.
    static func stageSynthesis(
        text: String,
        sessions: [Session],
        imageURL: (Session) -> URL,
        date: Date = Date()
    ) throws -> [URL] {
        let dir = stagingDirectory()
        var urls: [URL] = []

        var imageRefs: [(filename: String, createdAt: Date)] = []
        for session in sessions {
            let src = imageURL(session)
            let dstName = sourceImageFilename(session)
            let dst = dir.appendingPathComponent(dstName)
            do {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: src, to: dst)
                urls.append(dst)
                imageRefs.append((filename: dstName, createdAt: session.createdAt))
            } catch {
                // Skip silently — same as the web app, so a single
                // unreadable image doesn't break the export.
                continue
            }
        }

        let mdName = synthesisFilename(date: date)
        let mdURL = dir.appendingPathComponent(mdName)
        let body = synthesisMarkdown(
            text: text,
            sessionCount: sessions.count,
            date: date,
            imageRefs: imageRefs
        )
        try body.data(using: .utf8)?.write(to: mdURL, options: .atomic)
        urls.insert(mdURL, at: 0)
        return urls
    }

    // MARK: - Helpers

    private struct TimestampParts {
        let iso: String
        let ymd: String
        let hm: String
        let hms: String
    }

    private static func timestampParts(_ date: Date) -> TimestampParts {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        func pad(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }

        let ymd = "\(comps.year ?? 0)-\(pad(comps.month))-\(pad(comps.day))"
        let hm = "\(pad(comps.hour))\(pad(comps.minute))"
        let hms = "\(pad(comps.hour))\(pad(comps.minute))\(pad(comps.second))"
        return TimestampParts(
            iso: isoFormatter.string(from: date),
            ymd: ymd, hm: hm, hms: hms
        )
    }

    private static func slugify(_ source: String, maxWords: Int = 5, maxLen: Int = 50) -> String {
        if source.isEmpty { return "" }
        let stripped = source.replacingOccurrences(
            of: "[*`#_\\[\\]()<>]", with: " ", options: .regularExpression
        )
        let words = stripped
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(maxWords)
            .joined(separator: "-")
            .lowercased()
        let cleaned = words.replacingOccurrences(
            of: "[^a-z0-9-]+", with: "-", options: .regularExpression
        )
        let collapsed = cleaned.replacingOccurrences(
            of: "-+", with: "-", options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(maxLen))
    }

    /// Render a tiny YAML frontmatter block. Values can be `String`,
    /// `Int`, or `[String]`.
    private static func frontmatter(_ pairs: [(key: String, value: Any)]) -> String {
        var lines: [String] = ["---"]
        for (key, value) in pairs {
            if let arr = value as? [String] {
                lines.append("\(key):")
                for item in arr { lines.append("  - \(item)") }
            } else {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Per-call subdirectory under tmp so a re-stage doesn't clobber
    /// an in-flight share. iOS clears the temp directory on its own
    /// schedule; we don't try to GC.
    private static func stagingDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func stagingURL(name: String) -> URL {
        stagingDirectory().appendingPathComponent(name)
    }
}
