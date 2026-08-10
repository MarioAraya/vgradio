import SwiftUI
import AppKit

enum VGTheme: String, CaseIterable, Identifiable {
    case dark, light, auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark:  return "Oscuro"
        case .light: return "Claro"
        case .auto:  return "Auto"
        }
    }

    /// `nil` means "follow the system appearance".
    var appearance: NSAppearance? {
        switch self {
        case .dark:  return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .auto:  return nil
        }
    }
}

@Observable
final class ThemeStore {
    private static let key = "vgradio.theme"

    var theme: VGTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            apply()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? VGTheme.dark.rawValue
        theme = VGTheme(rawValue: raw) ?? .dark
    }

    /// Sets the app-wide appearance, which is what the dynamic `Color.vg*` tokens resolve against.
    func apply() {
        NSApp.appearance = theme.appearance
    }
}
