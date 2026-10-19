import AppKit
import Carbon.HIToolbox
import Testing
@testable import Inkey

@Suite("Configurable keyboard shortcuts", .serialized)
@MainActor
struct KeyboardShortcutTests {
    func withPreferences(_ body: (UserPreferences) throws -> Void) throws {
        _ = NSApplication.shared
        let suite = "InkeyShortcutsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(UserPreferences(defaults: defaults))
    }
    func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags, window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil, characters: KeyBinding.keyNames[code] ?? "", charactersIgnoringModifiers: KeyBinding.keyNames[code] ?? "", isARepeat: false, keyCode: code)!
    }
    @Test func defaultsAreCompleteUniqueAndKeepLegacyGlobalShortcut() throws {
        try withPreferences { preferences in
            let shortcuts = preferences.shortcuts
            #expect(ShortcutAction.allCases.count == 35)
            #expect(ShortcutAction.groups.flatMap(\.1).count == 35)
            for action in ShortcutAction.allCases {
                #expect(shortcuts.binding(for: action) == action.defaultBinding)
                #expect(shortcuts.conflict(for: action.defaultBinding, excluding: action) == nil)
            }
            preferences.defaults.set(40, forKey: "shortcutCode")
            preferences.defaults.set(Int(cmdKey | optionKey), forKey: "shortcutModifiers")
            preferences.defaults.set("⌥⌘K", forKey: "shortcutLabel")
            #expect(shortcuts.label(for: .toggleWindow) == "⌥⌘K")
            shortcuts.set(KeyBinding(11, [.command,.option], "b"), for: .eraser)
            #expect(preferences.defaults.string(forKey: "shortcutLabel") == "⌥⌘K")
            #expect(shortcuts.binding(for: .toggleWindow)?.keyCode == 40)
        }
    }
    @Test func overridesDisabledBindingsAndResetSurviveReload() throws {
        try withPreferences { preferences in
            let custom = KeyBinding(40, [.command,.option], "k")
            preferences.shortcuts.set(custom, for: .eraser)
            preferences.shortcuts.set(nil, for: .save)
            let restored = ShortcutSettings(defaults: preferences.defaults)
            #expect(restored.binding(for: .eraser) == custom)
            #expect(restored.binding(for: .save) == nil)
            #expect(restored.binding(for: .saveAs) == ShortcutAction.saveAs.defaultBinding)
            restored.set(nil, for: .toggleWindow)
            #expect(restored.binding(for: .toggleWindow) == nil)
            restored.resetAll()
            for action in ShortcutAction.allCases { #expect(restored.binding(for: action) == action.defaultBinding) }
            preferences.defaults.set(Data("broken".utf8), forKey: "keyboardShortcuts")
            #expect(restored.binding(for: .save) == ShortcutAction.save.defaultBinding)
        }
    }
    @Test func conflictChecksPhysicalKeysAndProtectsOrdinaryTyping() throws {
        try withPreferences { preferences in
            let shortcuts = preferences.shortcuts
            #expect(shortcuts.conflict(for: KeyBinding(1, .command, "S"), excluding: .eraser) == .save)
            #expect(shortcuts.validationMessage(KeyBinding(0, [], "a"), for: .eraser) != nil)
            #expect(shortcuts.validationMessage(KeyBinding(0, .shift, "a"), for: .shape1) != nil)
            #expect(shortcuts.validationMessage(KeyBinding(18, .shift, "1"), for: .shape1) == nil)
            #expect(shortcuts.validationMessage(KeyBinding(48, .command, "\t"), for: .save) != nil)
            #expect(shortcuts.validationMessage(KeyBinding(49, .command, " "), for: .save) != nil)
            #expect(shortcuts.binding(for: .save)?.matches(event(1, [.command,.capsLock,.numericPad])) == true)
            #expect(shortcuts.binding(for: .save)?.matches(event(1, [.command,.shift])) == false)
            #expect(KeyBinding(event: event(18, .shift)).label == "⇧1")
            let function = KeyBinding(event: event(122, []))
            #expect(function.label == "F1")
            #expect(shortcuts.validationMessage(function, for: .save) == nil)
        }
    }
    @Test func menusTooltipsAndRecorderUpdateTogetherWithoutOldBinding() throws {
        try withPreferences { preferences in
            let app = InkeyApp(preferences: preferences)
            let oldMenu = NSApp.mainMenu
            defer { NSApp.mainMenu = oldMenu }
            app.buildMenu()
            let window = app.makeSettingsWindow(); app.settings = window
            defer { window.close() }
            app.settingsTab?.selectedSegment = 1
            app.changeSettingsTab(app.settingsTab!)
            let recorder = try #require(app.shortcutRecorders[.eraser]?.first)
            recorder.beginRecording()
            recorder.keyDown(with: event(40, [.command,.option], window: window))
            #expect(!recorder.recording && recorder.title == "⌥⌘K")
            #expect(preferences.shortcuts.binding(for: .eraser)?.keyCode == 40)
            let menu = NSApp.mainMenu!.items.first { $0.title == "视图" }!.submenu!
            let item = try #require(menu.items.first { $0.action == #selector(InkeyApp.toggleEraser(_:)) })
            #expect(item.keyEquivalent == "k" && item.keyEquivalentModifierMask == [.command,.option])
            #expect(app.palette.subviews.contains { $0.toolTip?.contains("右键调节尺寸 · ⌥⌘K") == true })
            recorder.beginRecording()
            recorder.keyDown(with: event(12, .command, window: window))
            #expect(recorder.recording)
            #expect(app.shortcutPage?.message.stringValue.contains("退出") == true)
            recorder.keyDown(with: event(1, .command, window: window))
            #expect(recorder.recording)
            let acceptedConflict = app.updateShortcut(.eraser, binding: KeyBinding(1, .command, "s"))
            #expect(acceptedConflict == false)
            #expect(preferences.shortcuts.binding(for: .eraser)?.keyCode == 40)
            #expect(app.shortcutPage?.message.stringValue.contains("保存") == true)
            recorder.beginRecording(); recorder.keyDown(with: event(53, [], window: window))
            #expect(recorder.title == "⌥⌘K")
            recorder.beginRecording(); recorder.keyDown(with: event(51, [], window: window))
            #expect(preferences.shortcuts.binding(for: .eraser) == nil)
            #expect(item.keyEquivalent.isEmpty && recorder.title == "未设置")
            recorder.resetShortcut()
            #expect(item.keyEquivalent == "e" && recorder.title == "⌥⌘E")
        }
    }
    @Test func customShapeAndColorPositionsFollowOrderAndRespectComposition() throws {
        try withPreferences { preferences in
            preferences.shapeOrder = [.ellipse,.line,.rectangle,.arrow]
            preferences.shortcuts.set(KeyBinding(40, [.command,.option], "k"), for: .shape1)
            preferences.shortcuts.set(KeyBinding(11, [.command,.option], "b"), for: .color2)
            let app = InkeyApp(preferences: preferences)
            app.buildWindow(); app.canvas.onChange = nil
            defer { app.window.orderOut(nil) }
            #expect(!app.handleConfiguredShortcut(event(18, .shift, window: app.window)))
            #expect(app.handleConfiguredShortcut(event(40, [.command,.option], window: app.window)))
            #expect(app.canvas.shiftShape == .ellipse)
            #expect(app.handleConfiguredShortcut(event(11, [.command,.option], window: app.window)))
            #expect(app.canvas.ink == app.palette.colors[1])
            preferences.shapeOrder = [.rectangle,.line,.ellipse,.arrow]
            #expect(app.handleConfiguredShortcut(event(40, [.command,.option], window: app.window)))
            #expect(app.canvas.shiftShape == .rectangle)
            app.canvas.beginText(at: NSPoint(x: 100, y: 100))
            let text = try #require(app.canvas.subviews.compactMap { $0 as? InlineTextView }.first)
            text.setMarkedText("ni", selectedRange: NSRange(location: 2,length: 0), replacementRange: NSRange(location: NSNotFound,length: 0))
            #expect(!app.handleConfiguredShortcut(event(40, [.command,.option], window: app.window)))
            #expect(text.hasMarkedText())
        }
    }
    @Test func customPreciseEditAndToolbarVisibilityReplaceTheirDefaults() throws {
        try withPreferences { preferences in
            preferences.shortcuts.set(KeyBinding(40, [.command,.option], "k"), for: .preciseEdit)
            preferences.shortcuts.set(KeyBinding(11, [.command,.option], "b"), for: .hideToolbar)
            let app = InkeyApp(preferences: preferences)
            app.buildWindow(); app.canvas.onChange = nil
            defer { app.window.orderOut(nil) }
            app.canvas.beginText(at: NSPoint(x: 100,y: 100))
            let text = try #require(app.canvas.subviews.compactMap { $0 as? InlineTextView }.first)
            text.insertText("left", replacementRange: NSRange(location: 0,length: 0))
            text.keyDown(with: event(40,[.command,.option],window: app.window))
            #expect(app.canvas.isPrecisionEditing)
            #expect(!app.handleConfiguredShortcut(event(36,.command,window: app.window)))
            let hidden = app.palette.isHidden
            #expect(!app.handleToolbarVisibilityShortcut(event(17,[.command,.shift],window: app.window)))
            #expect(app.handleToolbarVisibilityShortcut(event(11,[.command,.option],window: app.window)))
            #expect(app.palette.isHidden != hidden)
        }
    }
    @Test func searchFiltersAndRestoresAllRowsAndOnlyOneRecorderRecords() throws {
        try withPreferences { preferences in
            let app = InkeyApp(preferences: preferences)
            let window = app.makeSettingsWindow(); app.settings = window
            defer { window.close() }
            app.settingsTab!.selectedSegment = 1; app.changeSettingsTab(app.settingsTab!)
            let page = try #require(app.shortcutPage)
            #expect(page.allSubviews.compactMap { $0 as? ShortcutRecorder }.count == 35)
            page.searchField.stringValue = "橡皮"
            page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            page.layoutSubtreeIfNeeded()
            #expect(page.allSubviews.compactMap { $0 as? ShortcutRecorder }.count == 3)
            page.searchField.stringValue = "not-found"
            page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            #expect(page.allSubviews.contains { ($0 as? NSTextField)?.stringValue == "没有匹配的操作" })
            page.searchField.stringValue = ""
            page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            page.layoutSubtreeIfNeeded()
            #expect(page.allSubviews.compactMap { $0 as? ShortcutRecorder }.count == 35)
            let first = app.shortcutRecorders[.save]!.first!, second = app.shortcutRecorders[.open]!.first!
            first.beginRecording(); second.beginRecording()
            #expect(!first.recording && second.recording)
            app.settingsTab!.selectedSegment = 0; app.changeSettingsTab(app.settingsTab!)
            #expect(!second.recording)
        }
    }
}
