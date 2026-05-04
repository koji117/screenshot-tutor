// DocumentExporter.swift
// SwiftUI bridge to `UIDocumentPickerViewController(forExporting:)`.
//
// Why this exists: ShareLink with multiple items including a folder
// URL doesn't reliably preserve folder structure when the user picks
// "Save to Files" — iOS sometimes drops the folder, sometimes
// flattens it, sometimes copies just the .md and silently skips the
// `attachments/` directory. That breaks `![[attachments/...]]`
// wikilinks in Obsidian because the images never reach the vault.
//
// `UIDocumentPickerViewController(forExporting: asCopy:)` is the API
// designed for this: it presents a folder-pick UI and copies each
// URL into the chosen destination, preserving folders recursively.
// Result for `[mdURL, attachmentsDirURL]` exported to `_raw/`:
//
//     _raw/
//     ├── 2026-05-04-1430-foo.md
//     └── attachments/
//         └── 2026-05-04-1430-foo.jpg
//
// Exactly the layout the inline wikilinks expect.

import SwiftUI
import UIKit

struct DocumentExporter: UIViewControllerRepresentable {
    /// URLs to copy. Folders are copied recursively.
    let urls: [URL]
    /// Called with the destination URLs (one per item) on success,
    /// or with `[]` if the user cancelled.
    let onCompletion: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No-op — the picker is presented once and dismisses on its own.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: ([URL]) -> Void
        init(onCompletion: @escaping ([URL]) -> Void) {
            self.onCompletion = onCompletion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onCompletion(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion([])
        }
    }
}
