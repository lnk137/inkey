import Testing
import AppKit
@testable import Inkey

@Suite("Text and drawing routing", .serialized)
@MainActor
struct InputRoutingTests {
    let helper = CanvasTests()

    func makeEditor(_ canvas: CanvasView, text: String = "left") -> InlineTextView {
        canvas.beginText(at: NSPoint(x: 100, y: 100))
        let editor = canvas.subviews.compactMap { $0 as? InlineTextView }.first!
        editor.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        return editor
    }

    @Test func normalInputRoutesMouseThroughTextToCanvas() throws {
        let (_, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas)
        let point = editor.convert(NSPoint(x: 8, y: 10), to: canvas.superview)
        #expect(canvas.hitTest(point) === canvas)
        #expect(editor.frame.width < 100)
        #expect(!canvas.isPrecisionEditing)
    }

    @Test func draggingStartingOnTypedWordDrawsInsteadOfSelecting() {
        let (window, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas)
        let start = editor.convert(NSPoint(x: 8, y: 10), to: nil)
        let end = NSPoint(x: start.x + 80, y: start.y - 20)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        #expect(canvas.isEditing)
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        #expect(!canvas.isEditing)
        #expect(canvas.draft.items.count == 2)
        #expect(canvas.draft.items.first?.text == "left")
        #expect(canvas.draft.items.last?.kind == .stroke)
        #expect(canvas.draft.items.last?.points.first == InkPoint(canvas.world(canvas.convert(start, from: nil))))
    }

    @Test func singleClickRepositionsCaretWithoutCreatingStrokeOrEndingInput() {
        let (window, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas)
        let point = editor.convert(NSPoint(x: 2, y: 10), to: nil)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, NSPoint(x: point.x + 1, y: point.y), window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, point, window: window))
        #expect(canvas.isEditing)
        #expect(editor.selectedRange().location <= 1)
        #expect(editor.selectedRange().length == 0)
        #expect(canvas.draft.items.isEmpty)
    }

    @Test func preciseEditingKeepsNativeHitTestingOnlyOverActualLines() {
        let (_, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas, text: "leftPointer\nx")
        canvas.promoteTextEditing()
        #expect(canvas.isPrecisionEditing)
        let inside = editor.convert(NSPoint(x: 6, y: 10), to: canvas.superview)
        #expect(canvas.hitTest(inside) === editor)
        let blankSecondLine = editor.convert(NSPoint(x: 90, y: 38), to: canvas.superview)
        #expect(canvas.hitTest(blankSecondLine) === canvas)
    }

    @Test func commandReturnPromotesInputAndOutsideDragCommitsAndDraws() {
        let (window, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas)
        editor.keyDown(with: helper.key("\r", window: window, keyCode: 36, modifiers: .command))
        #expect(canvas.isPrecisionEditing)
        let start = NSPoint(x: 400, y: 300), end = NSPoint(x: 460, y: 320)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        #expect(!canvas.isEditing)
        #expect(canvas.draft.items.count == 2)
    }

    @Test func doubleClickEntersPreciseEditingAndSelectsWord() {
        let (window, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas)
        let point = editor.convert(NSPoint(x: 8, y: 10), to: nil)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
        canvas.mouseDown(with: event)
        #expect(canvas.isPrecisionEditing)
        #expect(editor.selectedRange().length == 4)
        #expect(canvas.draft.items.isEmpty)
    }

    @Test func keyboardCorrectionsRemainNativeBeforeDrawing() {
        let (_, canvas) = helper.makeCanvas()
        let editor = makeEditor(canvas, text: "rigth")
        editor.setSelectedRange(NSRange(location: 3, length: 2))
        editor.insertText("ht", replacementRange: editor.selectedRange())
        editor.deleteBackward(nil)
        editor.insertText("t", replacementRange: editor.selectedRange())
        canvas.commitText()
        #expect(canvas.draft.items.first?.text == "right")
    }
}
