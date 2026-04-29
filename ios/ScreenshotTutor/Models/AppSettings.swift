// AppSettings.swift
// User-facing preferences that persist across launches but don't
// belong on a Session record. Currently just the output language.

import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {

    private static let langKey = "screenshot-tutor.lang"

    @Published var lang: Lang {
        didSet {
            UserDefaults.standard.set(lang.rawValue, forKey: Self.langKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.langKey) ?? Lang.en.rawValue
        self.lang = Lang(rawValue: raw) ?? .en
    }
}
