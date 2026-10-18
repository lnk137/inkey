import AppKit
import Testing
@testable import Inkey

@Suite("Single cursor and toolbar visibility", .serialized)
@MainActor
struct CursorToolbarTests {
    let helper = CanvasTests()
    let noReplacement = NSRange(location: NSNotFound, length: 0)

    @Test func movementHidesCaretWithoutSplittingTextOrReplacingInputContext() throws {
        try PointerInputTests().withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let text = PointerInputTests().setup(canvas)
            let context = try #require(text.inputContext)
            #expect(canvas.typingCaretVisible)
            let nearby = canvas.convert(NSPoint(x: 101, y: 100), to: nil)
            canvas.updatePointerLocation(nearby)
            #expect(!canvas.typingCaretVisible)
            #expect(text.insertionPointColor == .clear)
            #expect(canvas.isEditing && text.string == "left")
            #expect(!canvas.retargetTypingIfNeeded(helper.key("x", window: window), from: text, at: nearby))
            text.insertText("x", replacementRange: noReplacement)
            #expect(canvas.typingCaretVisible)
            #expect(text.insertionPointColor != .clear)
            #expect(window.firstResponder === text)
            #expect(text.inputContext === context)
            canvas.commitText()
            #expect(!canvas.typingCaretVisible)
            #expect(text.insertionPointColor == .clear)
            #expect(canvas.draft.items.map(\.text) == ["leftx"])
        }
    }

    @Test func preciseEditingAndCompositionHideCaretOnMoveAndResumeAtOriginalLocation() {
        let (window, canvas) = helper.makeCanvas()
        let text = PointerInputTests().setup(canvas)
        canvas.promoteTextEditing()
        let context = text.inputContext
        let target = canvas.convert(NSPoint(x: 400, y: 250), to: nil)
        canvas.updatePointerLocation(target)
        #expect(!canvas.typingCaretVisible)
        #expect(canvas.isPrecisionEditing)
        text.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: noReplacement)
        #expect(canvas.typingCaretVisible)
        canvas.updatePointerLocation(canvas.convert(NSPoint(x: 401, y: 250), to: nil))
        #expect(!canvas.typingCaretVisible)
        #expect(text.hasMarkedText())
        #expect(!canvas.retargetTypingIfNeeded(helper.key("hao", window: window), from: text, at: target))
        text.insertText("你好", replacementRange: noReplacement)
        #expect(canvas.typingCaretVisible)
        #expect(text.inputContext === context)
        #expect(canvas.draft.anchor == InkPoint(NSPoint(x: 100, y: 100)))
        canvas.commitText()
        #expect(canvas.draft.items.first?.text == "left你好")
    }

    @Test func crosshairRemainsTheMouseCursorOverTextAndEraser() {
        let (window, canvas) = helper.makeCanvas()
        let event = helper.mouse(.mouseMoved, .zero, window: window)
        let text = PointerInputTests().setup(canvas)
        canvas.promoteTextEditing()
        text.cursorUpdate(with: event)
        #expect(NSCursor.current == NSCursor.crosshair)
        canvas.setEraserEnabled(true)
        canvas.cursorUpdate(with: event)
        #expect(NSCursor.current == NSCursor.crosshair)
        #expect(!canvas.typingCaretVisible)
    }

    @Test func collapseHideAndRestorePreserveColorsToolsAndPreferences() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 320, height: 80), preferences: preferences)
        let originalColors = palette.colors
        palette.chooseShape(.rectangle)
        palette.toggleCollapsed()
        #expect(palette.isCollapsed && palette.frame.width == 36 && palette.frame.height == 36)
        #expect(palette.subviews.filter { !$0.isHidden }.count == 1)
        palette.choose(3)
        #expect(palette.isCollapsed)
        #expect(palette.subviews.compactMap { $0 as? SwatchButton }.allSatisfy { $0.isHidden })
        palette.setToolbarHidden(true)
        let restored = PaletteView(frame: palette.frame, preferences: preferences)
        #expect(restored.isHidden && restored.isCollapsed)
        #expect(preferences.shiftShape == .rectangle)
        restored.setToolbarHidden(false)
        #expect(restored.isCollapsed && !restored.isHidden)
        restored.toggleCollapsed()
        #expect(restored.frame.size == NSSize(width: 320, height: 80))
        #expect(restored.colors == originalColors)
        #expect(!preferences.toolbarCollapsed && !preferences.toolbarHidden)
    }

    @Test func hiddenToolbarDoesNotBlockPointerPlacementAndMenusCanRestoreIt() {
        let app = InkeyApp()
        // Application callbacks are not launched; the temporary window has no draft storage side effects.
        app.buildWindow()
        let collapsed = app.palette.isCollapsed, hidden = app.palette.isHidden
        defer {
            app.palette.setToolbarHidden(hidden)
            if app.palette.isCollapsed != collapsed { app.palette.toggleCollapsed() }
            app.window.orderOut(nil)
        }
        app.palette.setToolbarHidden(true)
        let point = app.palette.convert(NSPoint(x: app.palette.bounds.midX, y: app.palette.bounds.midY), to: nil)
        #expect(app.canvas.isCanvasLocation?(point) == true)
        app.toggleToolbarHidden(nil)
        #expect(!app.palette.isHidden)
        app.toggleToolbarCollapsed(nil)
        #expect(app.palette.isCollapsed != collapsed)
    }
}
