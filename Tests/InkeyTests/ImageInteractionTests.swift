import AppKit
import Testing
@testable import Inkey

@Suite("Image selection and transforms", .serialized)
@MainActor
struct ImageInteractionTests {
    let helper = CanvasTests()
    func image() -> InkItem {
        InkItem(kind: .image, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], imageData: Data([1, 2, 3]), imageWidth: 200, imageHeight: 120)
    }
    func doubleClick(_ point: NSPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 2, pressure: 1)!
    }

    @Test func doubleClickSelectsAndDraggingMovesAtEveryZoomWithUndo() throws {
        for zoom in [0.5, 1.0, 2.0] {
            let (window, canvas) = helper.makeCanvas()
            canvas.draft.zoom = zoom
            canvas.draft.offset = InkPoint(NSPoint(x: 20, y: 30))
            let original = image()
            canvas.draft.items = [original]
            let start = canvas.convert(canvas.screen(NSPoint(x: 150, y: 140)), to: nil)
            canvas.mouseDown(with: doubleClick(start, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, start, window: window))
            #expect(canvas.selection == original.id)
            #expect(canvas.imageBoxFrame != nil)
            #expect(canvas.undoManager?.canUndo == false)
            let end = NSPoint(x: start.x + 60, y: start.y - 30)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            var moved = original
            moved.translate(x: 60 / zoom, y: 30 / zoom)
            #expect(canvas.draft.items == [moved])
            canvas.undo(nil)
            #expect(canvas.draft.items == [original])
            #expect(canvas.undoManager?.canUndo == false)
            canvas.redo(nil)
            #expect(canvas.draft.items == [moved])
        }
    }

    @Test func allCornersResizeProportionallyWithOppositeCornerFixed() throws {
        for zoom in [0.7, 1.0, 2.0] {
            for corner in TextResizeCorner.allCases {
                let (window, canvas) = helper.makeCanvas()
                canvas.draft.zoom = zoom
                let original = image()
                canvas.draft.items = [original]; canvas.selection = original.id
                let frame = try #require(canvas.imageBoxFrame)
                let startView = corner.point(in: frame)
                let endView = NSPoint(x: startView.x + (corner.isLeft ? -1 : 1) * original.imageWidth * zoom,
                                      y: startView.y + (corner.isTop ? -1 : 1) * original.imageHeight * zoom)
                let start = canvas.convert(startView, to: nil), end = canvas.convert(endView, to: nil)
                canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
                #expect(canvas.isDrawing)
                canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
                canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
                let resized = try #require(canvas.draft.items.first)
                #expect(abs(resized.imageWidth - 400) < 0.001)
                #expect(abs(resized.imageHeight - 240) < 0.001)
                #expect(resized.imageData == original.imageData && resized.id == original.id)
                let fixed = TextResizeCorner.allCases.first { $0.isLeft != corner.isLeft && $0.isTop != corner.isTop }!
                let before = fixed.point(in: original.bounds), after = fixed.point(in: resized.bounds)
                #expect(hypot(before.x - after.x, before.y - after.y) < 0.001)
                canvas.undo(nil)
                #expect(canvas.draft.items == [original] && canvas.undoManager?.canUndo == false)
                canvas.redo(nil)
                #expect(canvas.draft.items == [resized])
                let data = try JSONEncoder().encode(canvas.draft)
                #expect(try JSONDecoder().decode(Draft.self, from: data).items == [resized])
            }
        }
    }

    @Test func unselectedImageStillAllowsDrawingAndBlankClickDeselects() {
        let (window, canvas) = helper.makeCanvas()
        let original = image()
        canvas.draft.items = [original]
        let start = canvas.convert(NSPoint(x: 140, y: 130), to: nil)
        let end = NSPoint(x: start.x + 40, y: start.y)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        #expect(canvas.draft.items.last?.kind == .stroke)
        canvas.selection = original.id
        let blank = canvas.convert(NSPoint(x: 500, y: 400), to: nil)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, blank, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, blank, window: window))
        #expect(canvas.selection == nil && canvas.imageBoxFrame == nil)
    }
}
