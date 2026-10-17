import AppKit
import Testing
@testable import Inkey

@Suite("Text resizing and typing preferences", .serialized)
@MainActor
struct TextResizeTests {
    let helper = CanvasTests()
    let none = NSRange(location: NSNotFound, length: 0)
    func withPreferences(_ body: (UserPreferences) throws -> Void) throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(UserPreferences(defaults: defaults))
    }
    func makeCanvas(_ preferences: UserPreferences) -> (NSWindow, CanvasView) {
        let (window, _) = helper.makeCanvas()
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 820, height: 560), preferences: preferences)
        window.contentView = canvas
        return (window, canvas)
    }

    @Test func rightClickOpensSavedTextAndLeftDoubleClickStillDraws() throws {
        try withPreferences { preferences in
            let (window, canvas) = makeCanvas(preferences)
            let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], text: "variable")
            canvas.draft.items = [item]
            let point = canvas.convert(NSPoint(x: 108, y: 110), to: nil)
            let double = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
            canvas.mouseDown(with: double)
            #expect(!canvas.isPrecisionEditing)
            let end = NSPoint(x: point.x + 80, y: point.y)
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(canvas.draft.items.last?.kind == .stroke)
            canvas.rightMouseDown(with: helper.mouse(.rightMouseDown, point, window: window))
            #expect(canvas.isPrecisionEditing)
            #expect(canvas.textBoxFrame != nil)
            let editor = try #require(window.firstResponder as? InlineTextView)
            #expect(editor.selectedRange().length == item.text.count)
            editor.rightMouseDown(with: helper.mouse(.rightMouseDown, point, window: window))
            #expect(canvas.isPrecisionEditing)
        }
    }

    @Test func allFourCornersResizeWithFixedOppositeCornerAndOneUndoStep() throws {
        try withPreferences { preferences in
            for zoom in [0.7, 1.0, 2.0] {
                for corner in TextResizeCorner.allCases {
                    let (window, canvas) = makeCanvas(preferences)
                    canvas.draft.zoom = zoom
                    let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], text: "left你好", fontSize: 20)
                    canvas.draft.items = [item]; canvas.selection = item.id
                    let box = try #require(canvas.textBoxFrame)
                    let start = canvas.convert(corner.point(in: box), to: nil)
                    let delta = NSPoint(x: (corner.isLeft ? -1 : 1) * item.bounds.width * zoom, y: (corner.isTop ? -1 : 1) * item.bounds.height * zoom)
                    let endView = NSPoint(x: corner.point(in: box).x + delta.x, y: corner.point(in: box).y + delta.y)
                    let end = canvas.convert(endView, to: nil)
                    canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
                    #expect(canvas.isDrawing)
                    canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
                    canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
                    let resized = try #require(canvas.draft.items.first)
                    #expect(abs(resized.fontSize - 40) < 0.001)
                    #expect(resized.text == item.text && resized.color == item.color && resized.id == item.id)
                    let oldFixed = NSPoint(x: corner.isLeft ? item.bounds.maxX : item.bounds.minX, y: corner.isTop ? item.bounds.maxY : item.bounds.minY)
                    let newFixed = NSPoint(x: corner.isLeft ? resized.bounds.maxX : resized.bounds.minX, y: corner.isTop ? resized.bounds.maxY : resized.bounds.minY)
                    #expect(hypot(oldFixed.x - newFixed.x, oldFixed.y - newFixed.y) < 0.001)
                    #expect(abs(preferences.defaultFontSize - 40) < 0.001)
                    canvas.undo(nil); #expect(canvas.draft.items == [item])
                    #expect(canvas.undoManager?.canUndo == false)
                    canvas.redo(nil); #expect(canvas.draft.items == [resized])
                }
            }
        }
    }

    @Test func resizingLiveTextPreservesInputContextAndCanLeaveDefaultUnchanged() throws {
        try withPreferences { preferences in
            preferences.defaultFontSize = 24; preferences.resizeUpdatesDefaultFont = false
            let (window, canvas) = makeCanvas(preferences)
            canvas.beginText(at: NSPoint(x: 100, y: 100))
            let editor = try #require(window.firstResponder as? InlineTextView)
            let context = try #require(editor.inputContext)
            editor.insertText("你好", replacementRange: none)
            canvas.promoteTextEditing()
            let box = try #require(canvas.textBoxFrame)
            let startView = TextResizeCorner.bottomRight.point(in: box)
            let start = canvas.convert(startView, to: nil)
            let end = canvas.convert(NSPoint(x: startView.x + 80, y: startView.y + 50), to: nil)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(canvas.draft.items.first?.text == "你好")
            #expect(canvas.draft.items.first!.fontSize > 24)
            #expect(preferences.defaultFontSize == 24)
            #expect(window.firstResponder === editor && editor.inputContext === context)
            canvas.beginText(at: NSPoint(x: 400, y: 300))
            editor.insertText("next", replacementRange: none); canvas.commitText()
            #expect(canvas.draft.items.last?.fontSize == 24)
        }
    }

    @Test func fontPreferencesPersistClampAndApplyOnlyToNewText() throws {
        try withPreferences { preferences in
            #expect(preferences.defaultFontSize == 20 && preferences.resizeUpdatesDefaultFont)
            preferences.defaultFontSize = .nan; #expect(preferences.defaultFontSize == 20)
            preferences.defaultFontSize = 500; #expect(preferences.defaultFontSize == 200)
            preferences.defaultFontSize = -1; #expect(preferences.defaultFontSize == 6)
            preferences.defaultFontSize = 36; preferences.resizeUpdatesDefaultFont = false
            let restored = UserPreferences(defaults: preferences.defaults)
            #expect(restored.defaultFontSize == 36 && !restored.resizeUpdatesDefaultFont)
            let (window, canvas) = makeCanvas(preferences)
            canvas.beginText(at: NSPoint(x: 100, y: 100))
            let editor = try #require(window.firstResponder as? InlineTextView)
            editor.insertText("first", replacementRange: none)
            preferences.defaultFontSize = 48
            canvas.commitText()
            #expect(canvas.draft.items[0].fontSize == 36)
            canvas.beginText(at: NSPoint(x: 300, y: 200)); editor.insertText("second", replacementRange: none); canvas.commitText()
            #expect(canvas.draft.items[1].fontSize == 48)
            let original = canvas.draft.items[0]
            canvas.beginText(at: original.points[0].point, item: original)
            #expect(editor.font?.pointSize == 36)
        }
    }

    @Test func settingsApplyTypedFontSizeAndResizeDefaultWithoutChangingExistingText() throws {
        _ = NSApplication.shared
        let app = InkeyApp()
        let defaults = app.preferences.defaults
        let keys = ["defaultFontSize", "resizeUpdatesDefaultFont"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let window = app.makeSettingsWindow()
        let recorder = try #require(app.shortcutRecorder)
        recorder.performClick(nil)
        #expect(recorder.recording && recorder.title == "按下快捷键…")
        recorder.finishRecording()
        let field = try #require(app.fontSizeField)
        field.stringValue = "42"
        app.controlTextDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: field))
        #expect(app.preferences.defaultFontSize == 42)
        #expect(app.fontSizeStepper?.doubleValue == 42)
        field.stringValue = "999"
        app.changeDefaultFontSize(field)
        #expect(app.preferences.defaultFontSize == 42)
        let follow = try #require(window.contentView?.subviews.compactMap { $0 as? NSButton }.first { $0.title == "拖拽缩放后，设为下次输入字号" })
        follow.state = .off; app.changeResizeDefault(follow)
        #expect(!app.preferences.resizeUpdatesDefaultFont)
        #expect(app.canvas.draft.items.isEmpty)
    }

    @Test func shortcutRecorderAcceptsNewCombinationAndEscapeRestoresSavedLabel() throws {
        let (window, _) = helper.makeCanvas()
        let recorder = ShortcutRecorder(title: "⌃⌥Space", target: nil, action: nil)
        recorder.savedLabel = "⌃⌥Space"; recorder.recording = true
        var recorded: (UInt32, UInt32, String)?
        recorder.onRecord = { recorded = ($0, $1, $2); return true }
        recorder.keyDown(with: helper.key("k", window: window, keyCode: 40, modifiers: [.control, .option]))
        #expect(recorded?.0 == 40 && recorded?.2 == "⌃⌥K")
        #expect(!recorder.recording && recorder.title == "⌃⌥K")
        recorder.recording = true; recorder.title = "按下快捷键…"
        recorder.keyDown(with: helper.key("", window: window, keyCode: 53))
        #expect(!recorder.recording && recorder.title == "⌃⌥K")
    }
}
