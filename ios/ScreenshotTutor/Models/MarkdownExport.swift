// MarkdownExport.swift
// Port of the web app's `js/exports.js`. Two responsibilities:
//
//   1. Build the markdown body + Obsidian-style frontmatter for a
//      session or a synthesis (see `sessionMarkdown` /
//      `synthesisMarkdown`).
//   2. Stage the file(s) to a temp directory with an `attachments/`
//      subfolder for screenshots, then return a bundle of URLs the
//      caller can hand to `ShareLink`. When the user picks
//      "Save to Files" → vault folder, the .md and the
//      `attachments/` directory are both copied so the inline
//      `![[attachments/<filename>]]` wikilinks resolve in Obsidian.
//
// File naming and frontmatter shape match the web app exactly so
// markdown produced on either device drops into the same vault
// without surprises.

import Foundation
import UIKit

/// Subdirectory inside an export's staging folder where screenshots
/// live. Markdown wikilinks reference attachments via this prefix
/// (e.g. `![[attachments/2026-04-29-1430-foo.jpg]]`) so a "Save to
/// Files" of the staging contents into a vault folder lands the
/// images under the same `attachments/` subfolder there.
private let attachmentsDirName = "attachments"

/// Bundle of URLs produced by a stage call. `shareURLs` is what the
/// caller hands to `ShareLink(items:)` — both the markdown file and
/// the attachments folder are shared so iOS preserves the structure
/// when the user saves into their vault.
struct ExportBundle {
    /// Temp directory holding the staged contents.
    let stagingDir: URL
    /// Path to the markdown file inside `stagingDir`.
    let markdownURL: URL
    /// Path to the `attachments/` subdirectory, or nil if no images
    /// were staged.
    let attachmentsDir: URL?

    var shareURLs: [URL] {
        var urls: [URL] = [markdownURL]
        if let attachmentsDir { urls.append(attachmentsDir) }
        return urls
    }
}

enum MarkdownExport {

    // MARK: - Public: build markdown

    /// Markdown for a single session. Same structure as the web app's
    /// `buildSessionMarkdown`: frontmatter, summary, optional
    /// breakdown, optional chat thread.
    ///
    /// `attachedImageFilename` — the JPEG filename inside
    /// `attachments/`. When provided, an `![[attachments/<name>]]`
    /// embed is rendered immediately after the `# Screenshot summary`
    /// heading so the screenshot appears at the top of the note,
    /// where it's most relevant.
    static func sessionMarkdown(
        _ session: Session,
        attachedImageFilename: String? = nil
    ) -> String {
        let parts = timestampParts(session.createdAt)
        let fm = frontmatter([
            ("created", parts.iso),
            ("source", "screenshot-tutor"),
            ("tags", ["study", "screenshot"]),
        ])

        var lines: [String] = []
        lines.append("# Screenshot summary")
        lines.append("")

        if let filename = attachedImageFilename {
            lines.append("![[\(attachmentsDirName)/\(filename)]]")
            lines.append("")
        }

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

    /// Markdown for a synthesis. The `imageRefs` add a
    /// "Source screenshots" section with `![[attachments/...]]`
    /// wikilinks pointing at the staged attachments directory.
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
                lines.append("![[\(attachmentsDirName)/\(ref.filename)]]")
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

    /// JPEG filename used when bundling a session's screenshot into
    /// `attachments/`. Mirrors `sessionFilename` so the .md and its
    /// image share a slug, which keeps the vault tidy.
    static func sessionImageFilename(_ session: Session) -> String {
        let parts = timestampParts(session.createdAt)
        let slug = slugify(session.summary)
        let core = slug.isEmpty ? "screenshot" : slug
        return "\(parts.ymd)-\(parts.hm)-\(core).jpg"
    }

    /// Synthesis text usually opens with `1. **Themes** — A, B, C`
    /// because the prompt asks for that structure. Strip the leading
    /// list ordinal before slugifying so the filename starts with
    /// content (`themes-...`) instead of the section number
    /// (`1-themes-...`). Falls back to plain `synthesis` if the model
    /// produced nothing slug-worthy.
    static func synthesisFilename(text: String = "", date: Date = Date()) -> String {
        let parts = timestampParts(date)
        let cleaned = text.replacingOccurrences(
            of: #"^\s*(?:\d+[.)]|[-*])\s+"#,
            with: "",
            options: .regularExpression
        )
        let slug = slugify(cleaned)
        let core = slug.isEmpty ? "synthesis" : slug
        return "\(parts.ymd)-\(parts.hm)-\(core).md"
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

    /// Stage a session's markdown plus a copy of its screenshot into
    /// a fresh temp directory. The directory layout is:
    ///
    ///     export-<uuid>/
    ///     ├── 2026-04-29-1430-foo.md   (with ![[attachments/...jpg]])
    ///     └── attachments/
    ///         └── 2026-04-29-1430-foo.jpg
    ///
    /// Pass `bundle.shareURLs` to `ShareLink(items:)`. iOS shares the
    /// .md file and the `attachments/` folder as separate items, both
    /// dropping into whatever destination the user picks.
    static func stageSession(_ session: Session, sourceImageURL: URL?) throws -> ExportBundle {
        let dir = stagingDirectory()

        let mdName = sessionFilename(session)
        let mdURL = dir.appendingPathComponent(mdName)

        var attachmentsURL: URL?
        var attachedFilename: String?

        if let sourceImageURL,
           FileManager.default.fileExists(atPath: sourceImageURL.path) {
            let attDir = dir.appendingPathComponent(attachmentsDirName, isDirectory: true)
            try FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)
            let imageName = sessionImageFilename(session)
            let dst = attDir.appendingPathComponent(imageName)
            do {
                try FileManager.default.copyItem(at: sourceImageURL, to: dst)
                attachmentsURL = attDir
                attachedFilename = imageName
            } catch {
                // Same fail-soft behavior as synthesis: an unreadable
                // image shouldn't block the markdown export.
            }
        }

        let body = sessionMarkdown(session, attachedImageFilename: attachedFilename)
        try body.data(using: .utf8)?.write(to: mdURL, options: .atomic)

        return ExportBundle(stagingDir: dir, markdownURL: mdURL, attachmentsDir: attachmentsURL)
    }

    /// Stage the synthesis markdown plus copies of every session's
    /// JPEG into a fresh temp directory. Layout:
    ///
    ///     export-<uuid>/
    ///     ├── 2026-04-29-1430-synthesis.md
    ///     └── attachments/
    ///         ├── 2026-04-29-143012-foo-abc123.jpg
    ///         └── 2026-04-29-143205-bar-def456.jpg
    static func stageSynthesis(
        text: String,
        sessions: [Session],
        imageURL: (Session) -> URL,
        date: Date = Date()
    ) throws -> ExportBundle {
        let dir = stagingDirectory()
        let attDir = dir.appendingPathComponent(attachmentsDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)

        var imageRefs: [(filename: String, createdAt: Date)] = []
        for session in sessions {
            let src = imageURL(session)
            let dstName = sourceImageFilename(session)
            let dst = attDir.appendingPathComponent(dstName)
            do {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: src, to: dst)
                imageRefs.append((filename: dstName, createdAt: session.createdAt))
            } catch {
                continue
            }
        }

        let mdName = synthesisFilename(text: text, date: date)
        let mdURL = dir.appendingPathComponent(mdName)
        let body = synthesisMarkdown(
            text: text,
            sessionCount: sessions.count,
            date: date,
            imageRefs: imageRefs
        )
        try body.data(using: .utf8)?.write(to: mdURL, options: .atomic)

        // If no images copied successfully, drop the empty
        // `attachments/` directory so the share view doesn't show an
        // empty folder.
        let attachmentsResult: URL?
        if imageRefs.isEmpty {
            try? FileManager.default.removeItem(at: attDir)
            attachmentsResult = nil
        } else {
            attachmentsResult = attDir
        }

        return ExportBundle(
            stagingDir: dir,
            markdownURL: mdURL,
            attachmentsDir: attachmentsResult
        )
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

    /// Unicode-aware slug. Keeps any letter (`\p{L}`) or digit
    /// (`\p{N}`) — including CJK, Cyrillic, Greek, accented Latin —
    /// and replaces every other run of characters with a single
    /// hyphen. iOS / macOS / iCloud Drive / Obsidian all handle
    /// Unicode filenames cleanly, so a Japanese synthesis becomes
    /// `2026-05-04-1430-テーマ-機械学習-...md` instead of falling
    /// back to the `-synthesis.md` placeholder.
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
            of: #"[^\p{L}\p{N}-]+"#,
            with: "-",
            options: .regularExpression
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
}
