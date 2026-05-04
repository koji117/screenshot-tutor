// ImageZoomView.swift
// Full-screen viewer with pinch-to-zoom and pan, used for the
// session screenshot. The session list inline shows the image at
// max 360pt high so portrait screenshots get severely cropped;
// tapping the inline image presents this view so the user can read
// the full thing.

import SwiftUI
import UIKit

struct ImageZoomView: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 6

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomGesture)
                    .simultaneousGesture(panGesture)
                    .onTapGesture(count: 2, perform: doubleTap)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = clamp(lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= Self.minScale + 0.01 {
                    withAnimation(.spring(duration: 0.25)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func doubleTap() {
        withAnimation(.spring(duration: 0.25)) {
            if scale > Self.minScale + 0.01 {
                scale = Self.minScale
                lastScale = Self.minScale
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func clamp(_ s: CGFloat) -> CGFloat {
        min(max(s, Self.minScale), Self.maxScale)
    }
}
