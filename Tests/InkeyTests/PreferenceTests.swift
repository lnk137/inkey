import Testing
import Foundation
@testable import Inkey

@Suite("User preferences")
struct PreferenceTests {
    @Test func pointerDefaultsMigrateOnceAndToolbarChoicesPersist() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        preferences.migrateInteractionDefaults()
        #expect(defaults.bool(forKey: "pointerPlacement"))
        #expect(!preferences.toolbarCollapsed && !preferences.toolbarHidden)
        #expect(preferences.cursorTrail)
        preferences.cursorTrail = false
        preferences.toolbarCollapsed = true; preferences.toolbarHidden = true
        defaults.set(false, forKey: "pointerPlacement")
        let restored = UserPreferences(defaults: defaults)
        restored.migrateInteractionDefaults()
        #expect(!defaults.bool(forKey: "pointerPlacement"))
        #expect(!restored.cursorTrail)
        #expect(restored.toolbarCollapsed && restored.toolbarHidden)
    }
    @Test func toolSizeAndWindowModeSurviveNewPreferenceInstance() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        #expect(preferences.tool == .pen)
        #expect(preferences.eraserDiameter == 24)
        preferences.tool = .eraser; preferences.eraserDiameter = 56
        preferences.pinned = true; preferences.fullScreen = true
        let restored = UserPreferences(defaults: try #require(UserDefaults(suiteName: name)))
        #expect(restored.tool == .eraser)
        #expect(restored.eraserDiameter == 56)
        #expect(restored.pinned && restored.fullScreen)
    }

    @Test func invalidValuesFallBackOrClampSafely() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        defaults.set("unknown", forKey: "drawingTool")
        #expect(preferences.tool == .pen)
        preferences.eraserDiameter = -10; #expect(preferences.eraserDiameter == 4)
        preferences.eraserDiameter = 1000; #expect(preferences.eraserDiameter == 120)
        preferences.eraserDiameter = .nan; #expect(preferences.eraserDiameter == 24)
        defaults.set(Data("invalid".utf8), forKey: "lastLightInk")
        #expect(preferences.ink(dark: false) == nil)
        let bad = SavedInk(color: InkColor.light[0], slot: 99, isPreset: true)
        defaults.set(try JSONEncoder().encode(bad), forKey: "lastLightInk")
        #expect(preferences.ink(dark: false) == nil)
    }

    @Test func inkChoicesAreRememberedSeparatelyForEachPaperAppearance() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        let custom = SavedInk(color: InkColor("586E75"), slot: 2, isPreset: false)
        let preset = SavedInk(color: InkColor.dark[4], slot: 4, isPreset: true)
        preferences.saveInk(custom, dark: false); preferences.saveInk(preset, dark: true)
        let restored = UserPreferences(defaults: defaults)
        #expect(restored.ink(dark: false) == custom)
        #expect(restored.ink(dark: true) == preset)
    }
}
