import AppKit
import Testing
@testable import Inkey

@Suite("Selected text movement", .serialized)
@MainActor
struct TextMoveTests {
    let helper = CanvasTests()

    @Test func selectedTextMovesAtEveryZoomAndCreatesOneUndoStep() throws {
        for zoom in [0.7, 1.0, 2.0] {
            let (window, canvas) = helper.makeCanvas()
            canvas.draft.zoom = zoom
            canvas.draft.offset = InkPoint(NSPoint(x: 35, y: -20))
            let text = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 120, y: 100))], color: InkColor.light[0], text: "移动文字\nsecond line")
            let other = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 400, y: 300))], color: InkColor.light[1], text: "unchanged")
            canvas.draft.items = [text, other]
            canvas.selection = text.id
            let box = try #require(canvas.textBoxFrame)
            let startView = NSPoint(x: box.midX, y: box.midY)
            let start = canvas.convert(startView, to: nil)
            let end = canvas.convert(NSPoint(x: startView.x + 70, y: startView.y + 35), to: nil)
            #expect(canvas.canMoveText(at: start))
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            var expected = text
            expected.translate(x: 70 / zoom, y: 35 / zoom)
            let moved = try #require(canvas.draft.items.first)
            #expect(abs(moved.bounds.minX - expected.bounds.minX) < 0.001)
            #expect(abs(moved.bounds.minY - expected.bounds.minY) < 0.001)
            expected.points = moved.points
            #expect(canvas.draft.items == [expected, other])
            #expect(canvas.selection == text.id)
            #expect(!canvas.isDrawing)
            canvas.undo(nil)
            #expect(canvas.draft.items == [text, other])
            #expect(canvas.undoManager?.canUndo == false)
            canvas.redo(nil)
            #expect(canvas.draft.items == [expected, other])
        }
    }

    @Test func liveTextBorderRoutesToCanvasAndMovesWithoutLosingContent() throws {
        let (window, canvas) = helper.makeCanvas()
        canvas.beginText(at: NSPoint(x: 250, y: 180))
        let editor = try #require(window.firstResponder as? InlineTextView)
        let context = editor.inputContext
        editor.insertText("你好 move\nshort", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.promoteTextEditing()
        let box = try #require(canvas.textBoxFrame)
        let border = NSPoint(x: box.midX, y: box.minY)
        let start = canvas.convert(border, to: nil)
        #expect(canvas.canMoveText(at: start))
        #expect(editor.hitTest(border) == nil)
        let inside = NSPoint(x: editor.frame.minX + 15, y: editor.frame.minY + editor.frame.height / 4)
        #expect(!canvas.canMoveText(at: canvas.convert(inside, to: nil)))
        #expect(editor.hitTest(inside) === editor)
        for corner in TextResizeCorner.allCases {
            #expect(!canvas.canMoveText(at: canvas.convert(corner.point(in: box), to: nil)))
        }
        let originalOrigin = canvas.world(editor.frame.origin)
        let end = canvas.convert(NSPoint(x: border.x + 60, y: border.y - 30), to: nil)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        let moved = try #require(canvas.draft.items.first)
        #expect(moved.text == "你好 move\nshort")
        #expect(abs(moved.bounds.minX - originalOrigin.x - 60) < 0.001)
        #expect(abs(moved.bounds.minY - originalOrigin.y + 30) < 0.001)
        #expect(canvas.selection == moved.id)
        #expect(window.firstResponder === editor && editor.inputContext === context)
        canvas.undo(nil)
        #expect(canvas.draft.items.first?.points.first?.point == originalOrigin)
    }

    @Test func clickingSelectedBoxWithoutDraggingDoesNotAddUndoOrDraw() throws {
        let (window, canvas) = helper.makeCanvas()
        let text = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], text: "selected")
        canvas.draft.items = [text]
        canvas.selection = text.id
        let box = try #require(canvas.textBoxFrame)
        let point = canvas.convert(NSPoint(x: box.midX, y: box.minY), to: nil)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, point, window: window))
        #expect(canvas.draft.items == [text])
        #expect(canvas.selection == text.id)
        #expect(canvas.undoManager?.canUndo == false)
    }

    @Test func explicitEditingReservesAllInteriorSpaceForNativeSelection() throws {
        for zoom in [0.7, 1.0, 2.0] {
            let (window, canvas) = helper.makeCanvas()
            canvas.draft.zoom = zoom
            canvas.beginText(at: NSPoint(x: 200, y: 160))
            let editor = try #require(window.firstResponder as? InlineTextView)
            editor.insertText("a long first line\nx\n\nlast", replacementRange: NSRange(location: NSNotFound, length: 0))
            canvas.promoteTextEditing()
            // Sample every part of the interior, including empty multiline areas
            // and points immediately beside the border.
            for x in [0.1, editor.frame.width / 2, editor.frame.width - 0.1] {
                for y in [0.1, editor.frame.height / 2, editor.frame.height - 0.1] {
                    let point = NSPoint(x: editor.frame.minX + x, y: editor.frame.minY + y)
                    let windowPoint = canvas.convert(point, to: nil)
                    #expect(!canvas.canMoveText(at: windowPoint))
                    #expect(editor.hitTest(point) === editor)
                }
            }
            let box = try #require(canvas.textBoxFrame)
            for point in [NSPoint(x: box.midX, y: box.minY), NSPoint(x: box.midX, y: box.maxY), NSPoint(x: box.minX, y: box.midY), NSPoint(x: box.maxX - 0.1, y: box.midY)] {
                #expect(canvas.canMoveText(at: canvas.convert(point, to: nil)))
                #expect(editor.hitTest(point) == nil)
            }
        }
    }
}
