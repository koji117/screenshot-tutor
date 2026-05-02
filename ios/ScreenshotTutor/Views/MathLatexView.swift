// MathLatexView.swift
// SwiftUI wrapper around SwiftMath's `MTMathUILabel`. The model often
// emits LaTeX (`$\text{E}(X+Y) = \text{E}(X) + \text{E}(Y)$`) for
// textbook screenshots; without this, that text rendered as raw `$...$`
// noise. `MarkdownView` extracts those segments and hands them here for
// proper typesetting. `display: true` matches `$$...$$` (centered,
// larger); `display: false` matches `$...$` (text-style).

import SwiftUI
import SwiftMath

struct MathLatexView: UIViewRepresentable {
    let latex: String
    let display: Bool

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.labelMode = display ? .display : .text
        label.fontSize = display ? 18 : 16
        label.textAlignment = display ? .center : .left
        label.contentInsets = .zero
        label.textColor = .label
        // Disable horizontal compression so long expressions overflow
        // into a scroll view rather than getting truncated.
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        uiView.latex = latex
        uiView.labelMode = display ? .display : .text
        uiView.fontSize = display ? 18 : 16
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMathUILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? .infinity
        return uiView.sizeThatFits(CGSize(width: width, height: .infinity))
    }
}
