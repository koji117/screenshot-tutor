// MarkdownView.swift
// Lightweight markdown renderer for streamed model output. We split
// on blank lines so paragraphs/bullets get visual separation, and
// rely on SwiftUI's built-in inline markdown for **bold** / *italic* /
// `code`. No external dependency.
//
// This is intentionally not a full markdown engine — the model output
// is short, and a heavier renderer would add build complexity.

import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: String) -> some View {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)

        // If every line in the block starts with "- " or "* ", render
        // as a bullet list. Otherwise emit the block as a single Text
        // with newlines preserved so it reads as a paragraph.
        if lines.allSatisfy({ isBulletLine($0) }) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        inlineText(stripBullet(line))
                    }
                }
            }
        } else if let heading = headingLevel(lines.first ?? "") {
            // First line is a heading; render it then the rest of the block.
            let headingText = stripHeading(lines.first ?? "")
            let rest = lines.dropFirst().joined(separator: "\n")
            VStack(alignment: .leading, spacing: 6) {
                inlineText(headingText)
                    .font(headingFont(for: heading))
                    .fontWeight(.semibold)
                if !rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    inlineText(rest)
                }
            }
        } else {
            inlineText(block)
        }
    }

    private func inlineText(_ s: any StringProtocol) -> Text {
        // SwiftUI's `Text(LocalizedStringKey)` initializer interprets
        // markdown inline (bold/italic/code/links). We pass the raw
        // string in via LocalizedStringKey for that behaviour.
        Text(LocalizedStringKey(String(s)))
    }

    private func isBulletLine(_ line: any StringProtocol) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
    }

    private func stripBullet(_ line: any StringProtocol) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private func headingLevel(_ line: any StringProtocol) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("### ") { return 3 }
        if trimmed.hasPrefix("## ") { return 2 }
        if trimmed.hasPrefix("# ") { return 1 }
        return nil
    }

    private func stripHeading(_ line: any StringProtocol) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("### ") { return String(trimmed.dropFirst(4)) }
        if trimmed.hasPrefix("## ") { return String(trimmed.dropFirst(3)) }
        if trimmed.hasPrefix("# ") { return String(trimmed.dropFirst(2)) }
        return trimmed
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }
}
