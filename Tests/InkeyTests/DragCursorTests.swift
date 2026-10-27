import AppKit
import Testing
@testable import Inkey

@Suite("Canvas drag cursors", .serialized)
@MainActor
struct DragCursorTests {
    let helper = CanvasTests()

    @Test func selectedImageShowsOpenHandAndClosedHandDuringMovement() {
        for zoom in [0.7, 1.0, 2.0] {
            let (window, canvas) = helper.makeCanvas()
            canvas.draft.zoom = zoom
            let image = InkItem(kind: .image, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], imageWidth: 200, imageHeight: 120)
            canvas.draft.items = [image]
            let start = canvas.convert(canvas.screen(NSPoint(x: 180, y: 160)), to: nil)
            #expect(canvas.interactionCursor(at: start) == .crosshair)
            canvas.rightMouseDown(with: helper.mouse(.rightMouseDown, start, window: window))
            #expect(NSCursor.current == .openHand)
            canvas.mouseMoved(with: helper.mouse(.mouseMoved, start, window: window))
            #expect(NSCursor.current == .openHand)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            #expect(NSCursor.current == .closedHand)
            let end = NSPoint(x: start.x + 40, y: start.y - 20)
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            #expect(NSCursor.current == .closedHand)
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(NSCursor.current == .openHand)
            let outside = canvas.convert(NSPoint(x: 700, y: 500), to: nil)
            canvas.mouseMoved(with: helper.mouse(.mouseMoved, outside, window: window))
            #expect(NSCursor.current == .crosshair)
        }
    }

    @Test func textBorderMovesButItsInteriorAndDrawingModifiersDoNot() throws {
        let (window, canvas) = helper.makeCanvas()
        canvas.beginText(at: NSPoint(x: 240, y: 160))
        let editor = try #require(window.firstResponder as? InlineTextView)
        editor.insertText("move text", replacementRange: NSRange(location: NSNotFound, length: 0))
        canvas.promoteTextEditing()
        let rect = try #require(canvas.textBoxFrame)
        let border = canvas.convert(NSPoint(x: rect.midX, y: rect.minY), to: nil)
        let inside = canvas.convert(NSPoint(x: editor.frame.midX, y: editor.frame.midY), to: nil)
        #expect(canvas.interactionCursor(at: border) == .openHand)
        #expect(canvas.interactionCursor(at: inside) == .crosshair)
        #expect(canvas.interactionCursor(at: border, modifiers: .shift) == .crosshair)
        #expect(canvas.interactionCursor(at: border, modifiers: canvas.preferences.temporaryEraserModifier.flag) == .crosshair)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, border, window: window))
        #expect(NSCursor.current == .closedHand)
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, border, window: window))
        #expect(NSCursor.current == .openHand)
    }

    @Test func imageCornersShowTheirResizeDirectionAndKeepItThroughoutDrag() throws {
        for corner in TextResizeCorner.allCases {
            let (window, canvas) = helper.makeCanvas()
            let image = InkItem(kind: .image, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], imageWidth: 200, imageHeight: 120)
            canvas.draft.items = [image]; canvas.selection = image.id
            let rect = try #require(canvas.imageBoxFrame)
            let start = canvas.convert(corner.point(in: rect), to: nil)
            canvas.mouseMoved(with: helper.mouse(.mouseMoved, start, window: window))
            #expect(NSCursor.current == corner.resizeCursor)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            let end = NSPoint(x: start.x + 60, y: start.y - 60)
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            #expect(NSCursor.current == corner.resizeCursor)
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(!canvas.isDrawing)
        }
    }
}
