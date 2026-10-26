import AppKit
import Testing
@testable import Inkey

private final class HoverTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@Suite("Quiet hover editing", .serialized)
@MainActor
struct TextHoverTests {
    let helper = CanvasTests()

    func setup() -> (NSWindow, CanvasView, NSPoint) {
        _ = NSApplication.shared
        let window = HoverTestWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 820, height: 560))
        window.contentView = canvas
        let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], text: "hover 你好\nx")
        canvas.draft.items = [item]
        return (window, canvas, canvas.convert(NSPoint(x: 120, y: 110), to: nil))
    }

    @Test func dwellEntersWithoutBoxCaretSelectionOrDocumentChanges() throws {
        let (window, canvas, point) = setup()
        let original = canvas.draft.items
        canvas.updatePointerLocation(point)
        canvas.updateTextHover(at: point, time: 10)
        canvas.updateTextHover(at: point, time: 10.3)
        #expect(!canvas.isHoverEditing)
        canvas.updateTextHover(at: point, time: 10.46)
        #expect(canvas.isHoverEditing && canvas.isPrecisionEditing)
        #expect(canvas.textBoxFrame == nil)
        #expect(!canvas.typingCaretVisible)
        let editor = try #require(window.firstResponder as? InlineTextView)
        #expect(editor.selectedRange().length == 0)
        #expect(editor.hitTest(canvas.convert(point, from: nil)) === editor)
        editor.cursorUpdate(with: helper.mouse(.mouseMoved, point, window: window))
        #expect(NSCursor.current == .iBeam)
        canvas.commitText()
        #expect(canvas.draft.items == original)
        #expect(canvas.undoManager?.canUndo == false)
    }

    @Test func passingOverTextAndPressingImmediatelyStillDraws() {
        let (window, canvas, point) = setup()
        canvas.updatePointerLocation(point)
        canvas.updateTextHover(at: point, time: 10)
        let moved = NSPoint(x: point.x + 20, y: point.y)
        canvas.updateTextHover(at: moved, time: 10.3)
        canvas.updateTextHover(at: moved, time: 10.6)
        #expect(!canvas.isHoverEditing)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, moved, window: window))
        canvas.updateTextHover(at: moved, time: 11)
        #expect(!canvas.isHoverEditing)
        let end = NSPoint(x: moved.x + 60, y: moved.y + 30)
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        #expect(canvas.draft.items.count == 2)
        #expect(canvas.draft.items.last?.kind == .stroke)
    }

    @Test func leavingRestoresDrawingAndRightClickStillShowsHandles() throws {
        let (window, canvas, point) = setup()
        canvas.updatePointerLocation(point)
        canvas.updateTextHover(at: point, time: 10)
        canvas.updateTextHover(at: point, time: 10.46)
        #expect(canvas.isHoverEditing)
        let outside = canvas.convert(NSPoint(x: 450, y: 350), to: nil)
        canvas.mouseMoved(with: helper.mouse(.mouseMoved, outside, window: window))
        #expect(!canvas.isPrecisionEditing)
        #expect(canvas.hitTest(canvas.convert(point, from: nil)) === canvas)
        canvas.rightMouseDown(with: helper.mouse(.rightMouseDown, point, window: window))
        #expect(canvas.isPrecisionEditing && !canvas.isHoverEditing)
        #expect(canvas.textBoxFrame != nil)
    }

    @Test func erasingAndMarkedInputPreventHoverPromotion() throws {
        let (window, canvas, point) = setup()
        canvas.setEraserEnabled(true)
        canvas.updateTextHover(at: point, time: 10)
        canvas.updateTextHover(at: point, time: 11)
        #expect(!canvas.isHoverEditing)
        canvas.setEraserEnabled(false)
        canvas.beginText(at: NSPoint(x: 300, y: 250))
        let editor = try #require(window.firstResponder as? InlineTextView)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.updateTextHover(at: point, time: 20)
        canvas.updateTextHover(at: point, time: 21)
        #expect(!canvas.isHoverEditing)
        #expect(editor.hasMarkedText())
    }
}
