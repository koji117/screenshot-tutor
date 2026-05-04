// MarkdownView.swift
// Lightweight markdown renderer for streamed model output. We split
// on blank lines so paragraphs/bullets get visual separation, and
// rely on SwiftUI's built-in inline markdown for **bold** / *italic* /
// `code`.
//
// We also handle one HTML construct: `<details><summary>…</summary>…
// </details>` blocks, which the breakdown prompt explicitly asks the
// model to emit for collapsible answers. Those render as native
// SwiftUI `DisclosureGroup` widgets rather than appearing as raw tag
// text. Keeping the model output unchanged means the same markdown
// still works in Obsidian (which interprets the tags natively) when
// the user exports.
//
// LaTeX math (`$...$` inline, `$$...$$` block) is extracted at the
// block level and rendered via `MathLatexView` (SwiftMath). When a
// block contains math, we lay out a vertical stack of text/math runs,
// so inline math breaks onto its own line. That trades reading flow
// for proper math typesetting — textbooks treat important formulas as
// visual breaks anyway, and SwiftUI doesn't compose UIViews inline
// with `Text` cleanly.
//
// This is intentionally not a full markdown engine — the model output
// is short and a heavier renderer would add build complexity.

import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseSegments(text).enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Segments

    /// One contiguous chunk of either plain markdown or a
    /// `<details>` block we need to render as a disclosure.
    private enum Segment {
        case markdown(String)
        case disclosure(summary: String, body: String)
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        switch segment {
        case .markdown(let s):
            blocksView(s)
        case .disclosure(let summary, let body):
            DisclosureGroup {
                blocksView(body)
                    .padding(.top, 6)
            } label: {
                inlineText(summary).fontWeight(.semibold)
            }
        }
    }

    /// Pre-process the raw text into a sequence of markdown / disclosure
    /// segments by walking `<details>…</details>` ranges in order. Tag
    /// matching is case-insensitive; an unclosed `<details>` falls back
    /// to plain markdown so the user at least sees the answer text.
    private func parseSegments(_ input: String) -> [Segment] {
        var segments: [Segment] = []
        var cursor = input.startIndex
        let detailsOpen = "<details"
        let detailsClose = "</details>"

        while cursor < input.endIndex,
              let openTagStart = input.range(
                of: detailsOpen,
                options: [.caseInsensitive],
                range: cursor..<input.endIndex
              ),
              let openTagEnd = input.range(
                of: ">",
                options: [],
                range: openTagStart.upperBound..<input.endIndex
              ),
              let closeTagRange = input.range(
                of: detailsClose,
                options: [.caseInsensitive],
                range: openTagEnd.upperBound..<input.endIndex
              )
        {
            let preText = String(input[cursor..<openTagStart.lowerBound])
            if !preText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdown(preText))
            }

            let inner = input[openTagEnd.upperBound..<closeTagRange.lowerBound]
            let (summary, body) = extractSummary(from: String(inner))
            segments.append(.disclosure(summary: summary, body: body))

            cursor = closeTagRange.upperBound
        }

        if cursor < input.endIndex {
            let tail = String(input[cursor..<input.endIndex])
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdown(tail))
            }
        }

        // If we never saw any <details>, the whole input is one segment.
        if segments.isEmpty {
            segments.append(.markdown(input))
        }
        return segments
    }

    /// Pull `<summary>…</summary>` out of a details body. Falls back
    /// to "Answer" if the model omitted the summary tag.
    private func extractSummary(from inner: String) -> (summary: String, body: String) {
        guard let openStart = inner.range(of: "<summary", options: [.caseInsensitive]),
              let openEnd = inner.range(of: ">", range: openStart.upperBound..<inner.endIndex),
              let closeRange = inner.range(
                of: "</summary>",
                options: [.caseInsensitive],
                range: openEnd.upperBound..<inner.endIndex
              )
        else {
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            return ("Answer", trimmed)
        }
        let summary = String(inner[openEnd.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var body = String(inner[..<openStart.lowerBound])
        body += inner[closeRange.upperBound..<inner.endIndex]
        return (
            summary.isEmpty ? "Answer" : summary,
            body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Blocks

    @ViewBuilder
    private func blocksView(_ text: String) -> some View {
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: String) -> some View {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        let runs = extractMathRuns(from: block)
        let hasMath = runs.contains { if case .math = $0 { return true } else { return false } }

        // Math-bearing blocks lose bullet/heading layout in favour of a
        // text/math vertical flow, since SwiftUI can't compose a UIView
        // (the math) inline with a `Text`. The visual cost is small —
        // formulas read better on their own line anyway.
        if hasMath {
            mathAwareView(runs: runs)
        } else if lines.allSatisfy({ isBulletLine($0) }) {
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

    // MARK: - Math runs

    private enum MathRun {
        case text(String)
        case math(latex: String, display: Bool)
    }

    /// Walk the block character-by-character, splitting on `$$...$$`
    /// (block math) and `$...$` (inline math). Only matches *closed*
    /// delimiters, so a half-streamed `$x +` stays as text until the
    /// closing `$` arrives. Inline math may not span newlines, which
    /// avoids accidentally swallowing two unrelated `$` signs across
    /// a paragraph break.
    ///
    /// After splitting, simple inline math (Greek letters + common
    /// operators) is collapsed back into Unicode text so it flows
    /// inline within bullets / bold / paragraphs instead of breaking
    /// the block into a vertical stack. SwiftMath still owns the
    /// genuinely complex math (\\frac, ^{}, _{}, etc.).
    private func extractMathRuns(from block: String) -> [MathRun] {
        var runs: [MathRun] = []
        var pending = ""
        var i = block.startIndex

        func flushPending() {
            if !pending.isEmpty {
                runs.append(.text(pending))
                pending = ""
            }
        }

        while i < block.endIndex {
            // $$...$$ — block math, may contain newlines.
            if block[i...].hasPrefix("$$") {
                let after = block.index(i, offsetBy: 2)
                if let close = block.range(of: "$$", range: after..<block.endIndex) {
                    flushPending()
                    let latex = String(block[after..<close.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    runs.append(.math(latex: latex, display: true))
                    i = close.upperBound
                    continue
                }
            }
            // $...$ — inline math, single line, non-empty body.
            if block[i] == "$" {
                let after = block.index(after: i)
                var j = after
                var found: String.Index? = nil
                while j < block.endIndex {
                    if block[j] == "\n" { break }
                    if block[j] == "$" { found = j; break }
                    j = block.index(after: j)
                }
                if let close = found, close > after {
                    flushPending()
                    let latex = String(block[after..<close])
                    runs.append(.math(latex: latex, display: false))
                    i = block.index(after: close)
                    continue
                }
            }
            pending.append(block[i])
            i = block.index(after: i)
        }
        flushPending()

        return Self.foldSimpleInlineMath(runs)
    }

    /// Map of common LaTeX commands to their Unicode equivalents.
    /// Greek letters cover the lion's share of inline math in study
    /// summaries (`\\mu`, `\\sigma`, `\\alpha`, ...); the operators
    /// catch ±, ≤, ≥, ≠, ∑, ∫, → and friends.
    private static let latexUnicodeMap: [String: String] = [
        // Lowercase Greek
        "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
        "\\epsilon": "ε", "\\varepsilon": "ε", "\\zeta": "ζ", "\\eta": "η",
        "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
        "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ",
        "\\omicron": "ο", "\\pi": "π", "\\varpi": "ϖ", "\\rho": "ρ",
        "\\varrho": "ϱ", "\\sigma": "σ", "\\varsigma": "ς", "\\tau": "τ",
        "\\upsilon": "υ", "\\phi": "φ", "\\varphi": "φ", "\\chi": "χ",
        "\\psi": "ψ", "\\omega": "ω",
        // Uppercase Greek
        "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
        "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Upsilon": "Υ",
        "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
        // Relations
        "\\le": "≤", "\\leq": "≤", "\\ge": "≥", "\\geq": "≥",
        "\\ne": "≠", "\\neq": "≠", "\\approx": "≈", "\\equiv": "≡",
        "\\sim": "∼", "\\simeq": "≃", "\\propto": "∝",
        // Arithmetic / logic
        "\\pm": "±", "\\mp": "∓", "\\times": "×", "\\div": "÷",
        "\\cdot": "·", "\\ast": "∗", "\\star": "⋆",
        // Set / logic
        "\\in": "∈", "\\notin": "∉", "\\subset": "⊂", "\\supset": "⊃",
        "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅", "\\varnothing": "∅",
        "\\forall": "∀", "\\exists": "∃", "\\neg": "¬",
        // Big operators (inline form — display form goes via SwiftMath)
        "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮",
        // Calculus / arrows
        "\\partial": "∂", "\\nabla": "∇", "\\infty": "∞",
        "\\to": "→", "\\rightarrow": "→", "\\leftarrow": "←",
        "\\Rightarrow": "⇒", "\\Leftarrow": "⇐",
        "\\leftrightarrow": "↔", "\\Leftrightarrow": "⇔",
        "\\mapsto": "↦",
        // Misc
        "\\sqrt": "√", "\\degree": "°", "\\dots": "…", "\\ldots": "…",
        "\\cdots": "⋯", "\\circ": "∘", "\\bullet": "•",
        // Spacing — drop entirely so `\,` and friends don't leak through
        "\\,": "", "\\:": "", "\\;": "", "\\!": "", "\\ ": " ",
        // Text-mode helpers the model occasionally emits
        "\\text": "", "\\mathrm": "", "\\mathbf": "", "\\mathit": "",
    ]

    /// Try to express a piece of LaTeX as plain Unicode. Returns nil
    /// for anything still containing markup (`\\frac`, `^`, `_`,
    /// braces, leftover `\\`-commands) — those need real math
    /// rendering via SwiftMath.
    private static func tryUnicodeMath(_ latex: String) -> String? {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Replace longest commands first so `\sigma` can't be partially
        // clobbered by a hypothetical shorter prefix (defensive — the
        // current map has no overlapping prefixes, but cheap insurance).
        var result = trimmed
        for (cmd, uni) in latexUnicodeMap.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: cmd, with: uni)
        }

        // If markup remains, this is real math — let SwiftMath handle it.
        let problematic: Set<Character> = ["\\", "{", "}", "^", "_"]
        if result.contains(where: { problematic.contains($0) }) {
            return nil
        }
        return result
    }

    /// Replace each `.math(_, display: false)` whose LaTeX is
    /// expressible in Unicode with a `.text` run, then merge adjacent
    /// `.text` runs back together. Result: simple inline math becomes
    /// part of the surrounding text and the block keeps its original
    /// shape (bullet, bold, paragraph). Block math (`$$...$$`) is
    /// untouched and still rendered via SwiftMath.
    private static func foldSimpleInlineMath(_ runs: [MathRun]) -> [MathRun] {
        let folded: [MathRun] = runs.map { run in
            if case .math(let latex, false) = run,
               let unicode = tryUnicodeMath(latex) {
                return .text(unicode)
            }
            return run
        }
        var merged: [MathRun] = []
        for run in folded {
            if case .text(let cur) = run,
               case .text(let prev) = merged.last {
                merged[merged.count - 1] = .text(prev + cur)
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    @ViewBuilder
    private func mathAwareView(runs: [MathRun]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .text(let s):
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        inlineText(trimmed)
                    }
                case .math(let latex, let display):
                    MathLatexView(latex: latex, display: display)
                        .frame(maxWidth: .infinity, alignment: display ? .center : .leading)
                }
            }
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
