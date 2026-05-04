// AppSettings.swift
// User-facing preferences that persist across launches but don't
// belong on a Session record. Consumed via @EnvironmentObject by
// SettingsView and the input-routing logic in ContentView.

import Foundation
import SwiftUI

/// What happens to a freshly-picked image (Photos / Camera). The
/// per-paste choice in EmptyStateView always overrides this; the
/// preference is only consulted for input methods that don't have
/// an explicit per-tap mode picker.
enum ImageMode: String, Codable, CaseIterable, Hashable {
    case crop
    case full

    var displayName: String {
        switch self {
        case .crop: return "Crop a region"
        case .full: return "Use full image"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {

    private static let langKey = "screenshot-tutor.lang"
    private static let imageModeKey = "screenshot-tutor.imageMode"

    @Published var lang: Lang {
        didSet {
            UserDefaults.standard.set(lang.rawValue, forKey: Self.langKey)
        }
    }

    /// Default mode for Photos and Camera picks. Paste has its own
    /// per-tap buttons so this preference doesn't apply there.
    @Published var imageMode: ImageMode {
        didSet {
            UserDefaults.standard.set(imageMode.rawValue, forKey: Self.imageModeKey)
        }
    }

    init() {
        let langRaw = UserDefaults.standard.string(forKey: Self.langKey) ?? Lang.en.rawValue
        self.lang = Lang(rawValue: langRaw) ?? .en

        let modeRaw = UserDefaults.standard.string(forKey: Self.imageModeKey) ?? ImageMode.crop.rawValue
        self.imageMode = ImageMode(rawValue: modeRaw) ?? .crop
    }
}
