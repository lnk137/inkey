import Foundation

/// Interface language is fixed for the process so existing AppKit views stay consistent.
enum InterfaceLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    static func selected(in defaults: UserDefaults) -> InterfaceLanguage {
        InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .chinese
    }
}

enum Localization {
    static let current = InterfaceLanguage.selected(in: .standard)

    static func bundle(for language: InterfaceLanguage) -> Bundle? {
        func localizedBundle(in root: Bundle) -> Bundle? {
            guard let path = root.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
            return Bundle(path: path)
        }
        if let bundle = localizedBundle(in: .main) { return bundle }
        // A packaged app has no SwiftPM resource bundle; let the caller fall back to English.
        if Bundle.main.bundleURL.pathExtension == "app" { return nil }
#if SWIFT_PACKAGE
        if let bundle = localizedBundle(in: .module) { return bundle }
#endif
#if README_ASSETS
        if let resources = Bundle(path: FileManager.default.currentDirectoryPath + "/Sources/Inkey/Resources"),
           let bundle = localizedBundle(in: resources) { return bundle }
#endif
        return nil
    }

    static func text(_ key: String, language: InterfaceLanguage = current) -> String {
        if let bundle = bundle(for: language) {
            let result = bundle.localizedString(forKey: key, value: nil, table: nil)
            if result != key { return result }
        }
        return bundle(for: .english)?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

func localized(_ key: String, arguments: [String] = [], language: InterfaceLanguage = Localization.current) -> String {
    let text = Localization.text(key, language: language)
    guard !arguments.isEmpty else { return text }
    return String(format: text, arguments: arguments)
}
