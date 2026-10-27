import AppKit
import Testing
@testable import Inkey

@Suite("Shape selection and transforms", .serialized)
@MainActor
struct ShapeInteractionTests {
    let helper = CanvasTests()
    func shape(_ kind: InkKind) -> InkItem {
        InkItem(kind: kind, points: [InkPoint(NSPoint(x: 100, y: 100)), InkPoint(NSPoint(x: 280, y: 220))], color: InkColor.light[2], lineWidth: 4)
    }
    func location(_ point: NSPoint, _ canvas: CanvasView) -> NSPoint { canvas.convert(canvas.screen(point), to: nil) }
    func drag(_ start: NSPoint, _ end: NSPoint, _ canvas: CanvasView, _ window: NSWindow) {
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
    }

    @Test func rightClickSelectsAndMovesAllShapesWithOneUndoAtEveryZoom() throws {
        for kind in [InkKind.arrow, .line, .rectangle, .ellipse, .square] {
            for zoom in [0.5, 1.0, 2.0] {
                let (window, canvas) = helper.makeCanvas()
                canvas.draft.zoom = zoom; canvas.draft.offset = InkPoint(NSPoint(x: 20, y: 30))
                canvas.transparentBackground = zoom != 1
                canvas.setHighContrast(zoom == 2, animated: false)
                let original = shape(kind)
                canvas.draft.items = [original]
                let start = location(NSPoint(x: 190, y: 160), canvas)
                canvas.rightMouseDown(with: helper.mouse(.rightMouseDown, start, window: window))
                #expect(canvas.selection == original.id && !canvas.isEditing)
                #expect(canvas.interactionCursor(at: start) == .openHand)
                let end = NSPoint(x: start.x + 40, y: start.y - 20)
                drag(start, end, canvas, window)
                var expected = original; expected.translate(x: 40 / zoom, y: 20 / zoom)
                #expect(canvas.draft.items == [expected])
                canvas.undo(nil)
                #expect(canvas.draft.items == [original] && canvas.undoManager?.canUndo == false)
                canvas.redo(nil)
                #expect(canvas.draft.items == [expected])
                #expect(try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(canvas.draft)).items == [expected])
            }
        }
    }

    @Test func cornersResizeClosedShapesWithFixedOppositeCornerAndNoStyleChanges() throws {
        for kind in [InkKind.rectangle, .ellipse, .square] {
            for corner in TextResizeCorner.allCases {
                for zoom in [0.5, 2.0] {
                    let (window, canvas) = helper.makeCanvas()
                    canvas.draft.zoom = zoom
                    canvas.transparentBackground = zoom == 0.5
                    canvas.setHighContrast(zoom == 2, animated: false)
                    let original = shape(kind)
                    canvas.draft.items = [original]; canvas.selection = original.id
                    let box = try #require(canvas.shapeBoxFrame)
                    let start = canvas.convert(corner.point(in: box), to: nil)
                    #expect(!canvas.canMoveShape(at: start))
                    #expect(canvas.shapeResizeHandle(at: start) == corner)
                    let end = NSPoint(x: start.x + (corner.isLeft ? -40 : 40), y: start.y + (corner.isTop ? 30 : -30))
                    drag(start, end, canvas, window)
                    let resized = try #require(canvas.draft.items.first)
                    #expect(resized.shapeGeometry.width > original.shapeGeometry.width)
                    #expect(resized.shapeGeometry.height > original.shapeGeometry.height)
                    let opposite = TextResizeCorner.allCases.first { $0.isLeft != corner.isLeft && $0.isTop != corner.isTop }!
                    let before = opposite.point(in: original.shapeGeometry), after = opposite.point(in: resized.shapeGeometry)
                    #expect(hypot(before.x - after.x, before.y - after.y) < 0.001)
                    #expect(resized.color == original.color && resized.lineWidth == original.lineWidth && resized.kind == kind)
                    if kind == .square { #expect(abs(resized.bounds.width - resized.bounds.height) < 0.001) }
                    canvas.undo(nil)
                    #expect(canvas.draft.items == [original] && canvas.undoManager?.canUndo == false)
                }
            }
        }
    }

    @Test func arrowsAndLinesHaveIndependentEndpointHandlesWithNoJumpOrMoveConflict() throws {
        for kind in [InkKind.arrow, .line] {
            for endpoint in [0, 1] {
                for zoom in [0.5, 1.0, 2.0] {
                    let (window, canvas) = helper.makeCanvas()
                    canvas.draft.zoom = zoom
                    var original = shape(kind)
                    original.points[1].y = original.points[0].y // horizontal is not a degenerate box resize
                    canvas.draft.items = [original]; canvas.selection = original.id
                    #expect(canvas.shapeBoxFrame == nil)
                    let p = original.points[endpoint].point
                    let start = location(NSPoint(x: p.x + 3 / zoom, y: p.y), canvas)
                    #expect(canvas.shapeEndpointHandle(at: start) == endpoint)
                    #expect(!canvas.canMoveShape(at: start))
                    let end = NSPoint(x: start.x + 40, y: start.y - 70)
                    canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
                    canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, start, window: window))
                    #expect(canvas.draft.items == [original])
                    canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
                    canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
                    var expected = original
                    expected.points[endpoint].x += 40 / zoom; expected.points[endpoint].y += 70 / zoom
                    #expect(canvas.draft.items == [expected])
                    canvas.undo(nil)
                    #expect(canvas.draft.items == [original] && canvas.undoManager?.canUndo == false)
                    canvas.redo(nil); #expect(canvas.draft.items == [expected])
                }
            }
        }
    }

    @Test func gestureStaysLockedWhenPointerCrossesHandlesOrInterior() throws {
        let (window, canvas) = helper.makeCanvas()
        let original = shape(.rectangle)
        canvas.draft.items = [original]; canvas.selection = original.id
        let box = try #require(canvas.shapeBoxFrame)
        let center = canvas.convert(NSPoint(x: box.midX, y: box.midY), to: nil)
        let corner = canvas.convert(TextResizeCorner.bottomRight.point(in: box), to: nil)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, center, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, corner, window: window))
        #expect(canvas.interactionCursor(at: corner) == .closedHand)
        #expect(canvas.draft.items[0].bounds.size == original.bounds.size)
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, corner, window: window))
        canvas.undo(nil); canvas.selection = original.id
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, corner, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, center, window: window))
        #expect(canvas.interactionCursor(at: center) == TextResizeCorner.bottomRight.resizeCursor)
        #expect(canvas.draft.items[0].shapeGeometry.origin == original.shapeGeometry.origin)
        #expect(canvas.draft.items[0].bounds.size != original.bounds.size)
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, center, window: window))
    }

    @Test func unselectedShapesStillDrawAndSelectionCanBeDismissed() throws {
        let (window, canvas) = helper.makeCanvas()
        let original = shape(.ellipse)
        canvas.draft.items = [original]
        let center = location(NSPoint(x: 190, y: 160), canvas)
        drag(center, NSPoint(x: center.x + 30, y: center.y), canvas, window)
        #expect(canvas.draft.items.last?.kind == .stroke)
        canvas.rightMouseDown(with: helper.mouse(.rightMouseDown, center, window: window))
        #expect(canvas.selection == original.id)
        canvas.escape(); #expect(canvas.selection == nil)
        canvas.selection = original.id
        let blank = location(NSPoint(x: 500, y: 400), canvas)
        drag(blank, blank, canvas, window)
        #expect(canvas.selection == nil)
        // Tiny shapes retain a separate center movement target.
        var tiny = original; tiny.points[1] = InkPoint(NSPoint(x: 102, y: 102))
        canvas.draft.items = [tiny]; canvas.selection = tiny.id
        let rect = try #require(canvas.shapeBoxFrame)
        let middle = canvas.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        #expect(canvas.shapeResizeHandle(at: middle) == nil && canvas.canMoveShape(at: middle))
        var shortArrow = shape(.arrow)
        shortArrow.points[1] = InkPoint(NSPoint(x: 110, y: 100))
        canvas.draft.items = [shortArrow]; canvas.selection = shortArrow.id
        let shaft = location(NSPoint(x: 105, y: 100), canvas)
        #expect(canvas.shapeEndpointHandle(at: shaft) == nil && canvas.canMoveShape(at: shaft))
    }

    @Test func rightClickRespectsObjectOrderAndSelectedShapePreventsTextHover() {
        let (window, canvas) = helper.makeCanvas()
        let rectangle = shape(.rectangle)
        let text = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 140, y: 140))], color: InkColor.light[0], text: "covered text")
        canvas.draft.items = [text, rectangle]
        let point = location(NSPoint(x: 150, y: 150), canvas)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window, modifiers: .control))
        #expect(canvas.selection == rectangle.id && !canvas.isDrawing && !canvas.isEditing)
        canvas.updateTextHover(at: point, time: 0)
        canvas.updateTextHover(at: point, time: 1)
        #expect(!canvas.isHoverEditing && canvas.selection == rectangle.id)
        canvas.selection = nil; canvas.draft.items = [rectangle, text]
        canvas.rightMouseDown(with: helper.mouse(.rightMouseDown, point, window: window))
        #expect(canvas.isPrecisionEditing && canvas.selection == nil)
        canvas.commitText()
    }
}
