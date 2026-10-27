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
        #expect(localized("设置", "Settings", language: .english) == "Settings")
        #expect(localized("设置", "Settings", language: .chinese) == "设置")
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
