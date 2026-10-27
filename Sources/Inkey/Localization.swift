import Foundation

/// Interface language is fixed for the process so existing AppKit views stay consistent.
enum InterfaceLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    static func selected(in defaults: UserDefaults) -> InterfaceLanguage {
        InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .chinese
    }
}

enum Localization {
    static let current = InterfaceLanguage.selected(in: .standard)
}

func localized(_ chinese: String, _ english: String, language: InterfaceLanguage = Localization.current) -> String {
    language == .english ? english : chinese
}
