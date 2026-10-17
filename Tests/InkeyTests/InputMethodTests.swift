import AppKit
import Testing
@testable import Inkey

@Suite("Native input method lifecycle", .serialized)
@MainActor
struct InputMethodTests {
    let helper = CanvasTests()
    let noReplacement = NSRange(location: NSNotFound, length: 0)

    @Test func inputClientIsReadyBeforeTheFirstKeyAndSurvivesCommit() throws {
        let (window, canvas) = helper.makeCanvas()
        let client = try #require(window.firstResponder as? InlineTextView)
        let context = try #require(client.inputContext)
        #expect(!canvas.isEditing)
        client.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0), replacementRange: noReplacement)
        client.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: noReplacement)
        client.insertText("你好", replacementRange: noReplacement)
        #expect(client.string == "你好")
        #expect(!client.hasMarkedText())
        canvas.commitText()
        #expect(canvas.draft.items.map(\.text) == ["你好"])
        #expect(window.firstResponder === client)
        #expect(client.inputContext === context)
        #expect(!canvas.isEditing)
        #expect(client.string.isEmpty)
    }

    @Test func consecutivePinyinSessionsDoNotKeepInitialLatinLetters() throws {
        let (window, canvas) = helper.makeCanvas()
        let client = try #require(window.firstResponder as? InlineTextView)
        for (initial, pinyin, chinese) in [("n", "nihao", "你好"), ("d", "danwei", "单位")] {
            client.setMarkedText(initial, selectedRange: NSRange(location: 1, length: 0), replacementRange: noReplacement)
            client.setMarkedText(pinyin, selectedRange: NSRange(location: pinyin.utf16.count, length: 0), replacementRange: noReplacement)
            client.insertText(chinese, replacementRange: noReplacement)
            canvas.commitText()
            #expect(window.firstResponder === client)
        }
        #expect(canvas.draft.items.map(\.text) == ["你好", "单位"])
    }

    @Test func deliberateMixedTextAndEnglishVariablesAreNeverTrimmed() throws {
        let (window, canvas) = helper.makeCanvas()
        let client = try #require(window.firstResponder as? InlineTextView)
        for value in ["name", "distance", "n你好", "d单位"] {
            client.insertText(value, replacementRange: noReplacement)
            canvas.commitText()
        }
        #expect(canvas.draft.items.map(\.text) == ["name", "distance", "n你好", "d单位"])
    }

    @Test func pointerRelocationKeepsTheSameInputContext() throws {
        try PointerInputTests().withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let client = try #require(window.firstResponder as? InlineTextView)
            let context = try #require(client.inputContext)
            canvas.updatePointerLocation(canvas.convert(NSPoint(x: 100, y: 100), to: nil))
            canvas.beginText(at: NSPoint(x: 100, y: 100))
            client.insertText("left", replacementRange: noReplacement)
            let target = canvas.convert(NSPoint(x: 400, y: 250), to: nil)
            #expect(canvas.retargetTypingIfNeeded(helper.key("right", window: window), from: client, at: target))
            #expect(window.firstResponder === client)
            #expect(client.inputContext === context)
            #expect(client.string == "right")
        }
    }

    @Test func idleInputClientUsesCanvasUndoAndDrawingDoesNotReplaceIt() throws {
        let (window, canvas) = helper.makeCanvas()
        let client = try #require(window.firstResponder as? InlineTextView)
        client.insertText("node", replacementRange: noReplacement)
        canvas.commitText()
        #expect(client.undoManager === canvas.undoManager)
        let start = canvas.convert(NSPoint(x: 300, y: 300), to: nil)
        let end = canvas.convert(NSPoint(x: 340, y: 320), to: nil)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        #expect(window.firstResponder === client)
        canvas.undo(nil)
        #expect(canvas.draft.items.map(\.text) == ["node"])
        #expect(window.firstResponder === client)
    }
}
