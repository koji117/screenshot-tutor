// ImagePicker.swift
// Minimal SwiftUI wrapper around PhotosPicker. Returns a UIImage
// through the binding when the user picks an image; nil if they
// cancel. Used by the empty-state pick button.

import SwiftUI
import PhotosUI
import UIKit

struct ImagePickerButton: View {
    @Binding var image: UIImage?
    let label: String

    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            Text(label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onChange(of: item) { _, newItem in
            Task { await load(newItem) }
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
            await MainActor.run { self.image = ui }
        }
    }
}
