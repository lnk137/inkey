import AppKit
import Testing
@testable import Inkey

@Suite("Temporary eraser modifier", .serialized)
@MainActor
struct TemporaryEraserTests {
    let helper = CanvasTests()
    func fixture(_ body: (NSWindow, CanvasView, UserPreferences) throws -> Void) throws {
        _ = NSApplication.shared
        let suite = "InkeyTemporaryEraser.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserPreferences(defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 820, height: 560), preferences: preferences)
        window.contentView = canvas
        defer { canvas.flush(); window.close() }
        try body(window, canvas, preferences)
    }
    func line() -> InkItem {
        InkItem(kind: .stroke, points: [InkPoint(NSPoint(x: 100,y: 180)),InkPoint(NSPoint(x: 600,y: 180))], color: InkColor("303735"), lineWidth: 2)
    }
    func flags(_ modifiers: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
    }
    @Test func modifierPersistsAndInvalidValueFallsBack() throws {
        try fixture { _, _, preferences in
            #expect(preferences.temporaryEraserModifier == .option)
            preferences.temporaryEraserModifier = .command
            #expect(UserPreferences(defaults: preferences.defaults).temporaryEraserModifier == .command)
            preferences.defaults.set("invalid", forKey: "temporaryEraserModifier")
            #expect(preferences.temporaryEraserModifier == .option)
        }
    }
    @Test func commandErasesOptionMovesAndNeitherLatchesTheTool() throws {
        try fixture { window, canvas, preferences in
            preferences.temporaryEraserModifier = .command
            let original = line(); canvas.draft.items = [original]
            let point = canvas.convert(NSPoint(x: 300,y: 180), to: nil)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window, modifiers: .command))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, point, window: window))
            #expect(canvas.draft.items != [original] && !canvas.eraserEnabled)
            #expect(preferences.tool == .pen)
            canvas.undo(nil); #expect(canvas.draft.items == [original])
            let end = canvas.convert(NSPoint(x: 340,y: 210), to: nil)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window, modifiers: .option))
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window, modifiers: .option))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(canvas.draft.items.count == 1)
            #expect(canvas.draft.items[0].points[0] == InkPoint(NSPoint(x: 140,y: 210)))
        }
    }
    @Test func releaseMidDragStopsImmediatelyAndKeepsOneUndoStep() throws {
        try fixture { window, canvas, preferences in
            preferences.temporaryEraserModifier = .command
            let original = line(); canvas.draft.items = [original]
            let start = canvas.convert(NSPoint(x: 250,y: 180), to: nil)
            let next = canvas.convert(NSPoint(x: 300,y: 180), to: nil)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window, modifiers: .command))
            canvas.flagsChanged(with: flags([], window: window))
            let erased = canvas.draft.items
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, next, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, next, window: window))
            #expect(canvas.draft.items == erased && !canvas.eraserEnabled)
            canvas.undo(nil)
            #expect(canvas.draft.items == [original] && canvas.undoManager?.canUndo == false)
        }
    }
    @Test func missingFlagsEventAndFocusLossAlsoStopTemporaryErase() throws {
        try fixture { window, canvas, preferences in
            preferences.temporaryEraserModifier = .command
            canvas.draft.items = [line()]
            let start = canvas.convert(NSPoint(x: 250,y: 180), to: nil)
            let next = canvas.convert(NSPoint(x: 400,y: 180), to: nil)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window, modifiers: .command))
            let erased = canvas.draft.items
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, next, window: window))
            #expect(canvas.draft.items == erased)
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, next, window: window))
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, next, window: window, modifiers: .command))
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            let afterFocusLoss = canvas.draft.items
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, start, window: window, modifiers: .command))
            #expect(canvas.draft.items == afterFocusLoss && !canvas.isDrawing)
        }
    }
    @Test func settingsPickerChangesModifierWithoutChangingShortcutBindings() throws {
        try fixture { _, _, preferences in
            let app = InkeyApp(preferences: preferences)
            let window = app.makeSettingsWindow()
            defer { window.close() }
            let page = try #require(app.shortcutPage)
            let global = preferences.shortcuts.binding(for: .toggleWindow)
            page.temporaryEraserPicker.selectItem(at: 1)
            page.changeTemporaryEraser(page.temporaryEraserPicker)
            #expect(preferences.temporaryEraserModifier == .command)
            #expect(preferences.shortcuts.binding(for: .toggleWindow) == global)
            #expect(page.message.stringValue.contains("Command"))
        }
    }
}
