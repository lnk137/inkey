import AppKit
import Testing
@testable import Inkey

@Suite("Interface language", .serialized)
@MainActor
struct LocalizationTests {
    @Test func preferencesDefaultAndRoundTripWithoutTouchingUserSettings() throws {
        let suite = "InkeyLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(InterfaceLanguage.selected(in: defaults) == .chinese)
        defaults.set("en", forKey: "interfaceLanguage")
        #expect(InterfaceLanguage.selected(in: defaults) == .english)
        defaults.set("invalid", forKey: "interfaceLanguage")
        #expect(InterfaceLanguage.selected(in: defaults) == .chinese)
        #expect(localized("ui.settings", language: .english) == "Settings…")
        #expect(localized("ui.settings", language: .chinese) == "设置…")
    }

@Test func resourceKeysAndFormatArgumentsMatch() throws {
    func table(_ language: InterfaceLanguage) throws -> [String: String] {
        let bundle = try #require(Localization.bundle(for: language))
        let url = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String])
    }
    let english = try table(.english)
    let chinese = try table(.chinese)
    #expect(!english.isEmpty)
    #expect(Set(english.keys) == Set(chinese.keys))
    let placeholder = try NSRegularExpression(pattern: #"%[0-9]+\$@"#)
    func placeholders(_ value: String) -> [String] {
        let range = NSRange(value.startIndex..., in: value)
        return placeholder.matches(in: value, range: range).compactMap { Range($0.range, in: value).map { String(value[$0]) } }.sorted()
    }
    for key in english.keys {
        #expect(placeholders(english[key]!) == placeholders(chinese[key]!), "Mismatched placeholders: \(key)")
    }
    #expect(localized("ui.shape_position_value", arguments: ["3"], language: .english) == "Shape position 3")
    #expect(localized("ui.shape_position_value", arguments: ["3"], language: .chinese) == "形状位置 3")
    #expect(localized("ui.missing_key", language: .english) == "ui.missing_key")

    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Inkey")
    let keyPattern = try NSRegularExpression(pattern: #""(ui\.[a-z0-9_]+)""#)
    for url in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil) where url.pathExtension == "swift" {
        let source = try String(contentsOf: url, encoding: .utf8)
        let range = NSRange(source.startIndex..., in: source)
        for match in keyPattern.matches(in: source, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
            let key = String(source[keyRange])
            #expect(english[key] != nil, "Missing resource for \(key) in \(url.lastPathComponent)")
        }
    }
}

    @Test func settingsShowsSelectedLanguageWithoutChangingPreferences() throws {
        _ = NSApplication.shared
        let suite = "InkeyLanguageSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("en", forKey: "interfaceLanguage")
        let app = InkeyApp(preferences: UserPreferences(defaults: defaults))
        let window = app.makeSettingsWindow()
        defer { window.close() }
        let selector = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSPopUpButton }.first { $0.itemTitles == ["简体中文", "English"] })
        #expect(selector.indexOfSelectedItem == 1)
        #expect(InterfaceLanguage.selected(in: defaults) == .english)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!selector.hasAmbiguousLayout)
        let tabs = try #require(app.settingsTab)
        #expect(!selector.frame.intersects(tabs.frame))
    }
}
