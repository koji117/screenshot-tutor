// CameraPicker.swift
// SwiftUI wrapper around UIImagePickerController for camera capture.
// PhotosPicker (used for Photos-library picking) doesn't expose the
// camera — UIKit is still the path for that.
//
// Used by the empty state's "Take a photo" button. The captured
// UIImage is published through the binding; the parent reacts in
// the same `onChange(of: pickedImage)` it already wires for the
// Photos picker.

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let captured = info[.originalImage] as? UIImage {
                parent.image = captured
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }
    }

    /// True when the device exposes a camera. iPads always do, but
    /// iOS Simulator does not — keep this guard so the button isn't
    /// shown in environments where tapping it would no-op.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}
