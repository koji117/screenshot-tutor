// RegionSelectorView.swift
// Drag-to-crop overlay shown after every image input. Equivalent of
// the web app's `selectRegion()` in `js/input.js` — gives the user a
// rectangle they can pull around any sub-region of the picked /
// captured / pasted screenshot before the model sees it. iPadOS
// doesn't expose partial-screen screenshots, so we do this step
// in-app.
//
// The view shows the image scaledToFit inside a GeometryReader; the
// selection rectangle is captured in *view* coordinates and converted
// to *image-pixel* coordinates only on confirm. That keeps the gesture
// math local without depending on the resolved image frame.
//
// "Use full image" skips cropping entirely, "Use selection" requires
// a non-trivial drag (>= 8px each side), and "Cancel" backs out
// without creating a session.

import SwiftUI
import UIKit

struct RegionSelectorView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    /// Drag start in view coordinates of the GeometryReader.
    @State private var dragStart: CGPoint?
    /// Drag current in view coordinates.
    @State private var dragEnd: CGPoint?

    private static let minSide: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            cropArea
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // The crop is gesture-only; VoiceOver users can't drag
            // a rectangle, so auto-confirm the full image and skip
            // this screen entirely. They can still review the
            // captured image inside the resulting session view.
            if UIAccessibility.isVoiceOverRunning {
                onConfirm(image)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        // GeometryReader-free width check via the horizontal size
        // class — when we're in a narrow width (Slide Over, 320pt
        // iPhone class), drop the hint text so the four buttons
        // don't get squeezed or wrap.
        ViewThatFits(in: .horizontal) {
            toolbarContent(showHint: true)
            toolbarContent(showHint: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95))
    }

    @ViewBuilder
    private func toolbarContent(showHint: Bool) -> some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
                .foregroundStyle(.white)

            Spacer()

            if showHint {
                Text(hintText)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .layoutPriority(0)
                Spacer()
            }

            Button("Use full image") {
                onConfirm(image)
            }
            .foregroundStyle(.white)

            Button {
                confirmSelection(in: lastContainerSize)
            } label: {
                Text("Use selection").bold()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasUsableSelection)
        }
    }

    // MARK: - Crop area

    @State private var lastContainerSize: CGSize = .zero

    @ViewBuilder
    private var cropArea: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let displayed = displayedImageRect(in: containerSize)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: containerSize.width, height: containerSize.height)

                if let rect = selectionRect() {
                    selectionOverlay(rect: rect, container: containerSize, displayed: displayed)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil { dragStart = clamp(value.startLocation, into: displayed) }
                        dragEnd = clamp(value.location, into: displayed)
                    }
                    .onEnded { _ in /* selection persists for confirm */ }
            )
            .onAppear { lastContainerSize = containerSize }
            .onChange(of: containerSize) { _, new in lastContainerSize = new }
        }
    }

    @ViewBuilder
    private func selectionOverlay(
        rect: CGRect, container: CGSize, displayed: CGRect
    ) -> some View {
        ZStack {
            // Dim everything outside the selection so the chosen
            // region pops. Drawn as four edge bands so SwiftUI doesn't
            // need a true mask op on the legacy renderer.
            Group {
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: container.width, height: rect.minY)
                    .position(x: container.width / 2, y: rect.minY / 2)
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: container.width, height: container.height - rect.maxY)
                    .position(
                        x: container.width / 2,
                        y: rect.maxY + (container.height - rect.maxY) / 2
                    )
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: rect.minX, height: rect.height)
                    .position(x: rect.minX / 2, y: rect.midY)
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: container.width - rect.maxX, height: rect.height)
                    .position(
                        x: rect.maxX + (container.width - rect.maxX) / 2,
                        y: rect.midY
                    )
            }

            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - Selection geometry

    private var hasUsableSelection: Bool {
        guard let r = selectionRect() else { return false }
        return r.width >= Self.minSide && r.height >= Self.minSide
    }

    private var hintText: String {
        hasUsableSelection
            ? "Drag to adjust · or use full image"
            : "Drag on the image to select a region"
    }

    private func selectionRect() -> CGRect? {
        guard let s = dragStart, let e = dragEnd else { return nil }
        return CGRect(
            x: min(s.x, e.x),
            y: min(s.y, e.y),
            width: abs(e.x - s.x),
            height: abs(e.y - s.y)
        )
    }

    // MARK: - Image display geometry

    /// Where the image actually lives within the container after
    /// `.scaledToFit()`. Used to clamp the drag and to convert
    /// selection coords into image pixels on confirm.
    private func displayedImageRect(in container: CGSize) -> CGRect {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imgSize.width, container.height / imgSize.height)
        let displayedWidth = imgSize.width * scale
        let displayedHeight = imgSize.height * scale
        let originX = (container.width - displayedWidth) / 2
        let originY = (container.height - displayedHeight) / 2
        return CGRect(x: originX, y: originY, width: displayedWidth, height: displayedHeight)
    }

    private func clamp(_ point: CGPoint, into rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    // MARK: - Confirm + crop

    private func confirmSelection(in container: CGSize) {
        guard let viewRect = selectionRect(), hasUsableSelection else { return }
        let displayed = displayedImageRect(in: container)

        // Translate from container coords to image-pixel coords:
        // 1. subtract the displayed image origin (drops letterboxing)
        // 2. divide by the displayed scale (back into pixels)
        let scale = displayed.width / image.size.width
        guard scale > 0 else { return }

        let pixelRect = CGRect(
            x: (viewRect.minX - displayed.minX) / scale,
            y: (viewRect.minY - displayed.minY) / scale,
            width: viewRect.width / scale,
            height: viewRect.height / scale
        )

        // Account for the orientation baked into the UIImage so the
        // CGImage crop lines up with what the user actually sees.
        guard let cropped = crop(image, to: pixelRect) else {
            // Fall back to the full image rather than failing silently.
            onConfirm(image)
            return
        }
        onConfirm(cropped)
    }

    private func crop(_ image: UIImage, to pixelRect: CGRect) -> UIImage? {
        // Render the UIImage with its current orientation into a
        // pixel-correct context, then crop the resulting CGImage.
        // Going through a renderer is cheaper than juggling
        // .imageOrientation by hand and works for HEIC/CG-rotated
        // sources straight from PhotosPicker.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalised = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cg = normalised.cgImage else { return nil }
        let bounded = pixelRect.integral.intersection(
            CGRect(origin: .zero, size: image.size)
        )
        guard !bounded.isEmpty, let cropped = cg.cropping(to: bounded) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
