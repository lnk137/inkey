import AppKit
import Testing
@testable import Inkey

extension NSView {
    var allSubviews: [NSView] { subviews.flatMap { [$0] + $0.allSubviews } }
}

@Suite("Settings window", .serialized)
@MainActor
struct SettingsWindowTests {
    @Test func groupedLayoutFitsAllControlsAndLongShortcutInBothAppearances() throws {
        _ = NSApplication.shared
        let suite = "InkeySettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = InkeyApp(preferences: UserPreferences(defaults: defaults))
        let window = app.makeSettingsWindow()
        defer { window.close() }
        let content = try #require(app.generalSettingsView)
        let recorder = try #require(app.shortcutRecorder)
        recorder.title = "⌃⌥⇧⌘Return"
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            content.layoutSubtreeIfNeeded()
            #expect(content.bounds.width == 520)
            #expect(content.bounds.height < 650)
            let labels = content.allSubviews.compactMap { $0 as? NSTextField }
            for title in ["通用", "文字输入", "画布与工具栏"] {
                #expect(labels.contains { $0.stringValue == title })
            }
            let controls = content.allSubviews.filter {
                $0 is NSSwitch || $0 is NSPopUpButton || $0 is NSButton || $0 is NSStepper || ($0 as? NSTextField)?.isEditable == true
            }
            #expect(controls.compactMap { $0 as? NSSwitch }.count == 4)
            #expect(controls.compactMap { $0 as? NSPopUpButton }.count == 2)
            for control in controls {
                let frame = content.convert(control.bounds, from: control)
                #expect(content.bounds.contains(frame))
                #expect(frame.width > 10 && frame.height > 10)
                #expect(!control.hasAmbiguousLayout, "\(type(of: control)): \(control.frame)")
            }
        }
        // System approval copy must fit the same row without moving controls over one another.
        app.loginLaunchHint?.stringValue = "请在系统“登录项”中允许，或关闭此开关取消"
        content.layoutSubtreeIfNeeded()
        let hint = try #require(app.loginLaunchHint)
        let toggle = try #require(app.loginLaunchSwitch)
        #expect(!content.convert(hint.bounds, from: hint).intersects(content.convert(toggle.bounds, from: toggle)))
    }
}
