import AppKit
import Testing
@testable import Inkey

@Suite("Shape alignment", .serialized)
@MainActor
struct ShapeSnapTests {
    @Test func snapsAxesAndEqualSidesAcrossZoomAndQuadrants() {
        for zoom in [0.5, 1.0, 2.0] {
            for signX in [-1.0, 1.0] {
                for signY in [-1.0, 1.0] {
                    let start = NSPoint(x: 30, y: 40)
                    for kind in [InkKind.arrow, .line] {
                        var snap = ShapeSnap()
                        let horizontal = snap.point(from: start, to: NSPoint(x: 30 + signX * 100, y: 40 + signY * 4 / zoom), kind: kind, zoom: zoom)
                        #expect(horizontal.y == start.y && snap.alignment == .horizontal)
                        let vertical = snap.point(from: start, to: NSPoint(x: 30 + signX * 4 / zoom, y: 40 + signY * 100), kind: kind, zoom: zoom)
                        #expect(vertical.x == start.x && snap.alignment == .vertical)
                    }
                    for kind in [InkKind.rectangle, .ellipse] {
                        var snap = ShapeSnap()
                        let result = snap.point(from: start, to: NSPoint(x: 30 + signX * 100, y: 40 + signY * (100 + 4 / zoom)), kind: kind, zoom: zoom)
                        #expect(abs(abs(result.x - start.x) - abs(result.y - start.y)) < 0.0001)
                        #expect(snap.alignment == .equalSides)
                    }
                }
            }
        }
    }

    @Test func feedbackOccursOncePerEntryAndSnapReleases() {
        let helper = CanvasTests(), (window, canvas) = CanvasTests().makeCanvas()
        canvas.shiftShape = .arrow
        var feedback = 0
        canvas.onShapeAlignment = { feedback += 1 }
        let start = NSPoint(x: 100, y: 100)
        func drag(_ point: NSPoint) { canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, point, window: window, modifiers: .shift)) }
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window, modifiers: .shift))
        drag(NSPoint(x: 200, y: 104)); drag(NSPoint(x: 210, y: 108))
        #expect(feedback == 1)
        drag(NSPoint(x: 220, y: 112)); drag(NSPoint(x: 230, y: 104))
        #expect(feedback == 2)
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, NSPoint(x: 230, y: 104), window: window))
        #expect(canvas.draft.items.first?.points.last?.point.y == canvas.draft.items.first?.points.first?.point.y)
        canvas.undo(nil); #expect(canvas.draft.items.isEmpty)
    }

    @Test func smallOrUnalignedGesturesRemainFree() {
        var snap = ShapeSnap()
        let small = NSPoint(x: 8, y: 1)
        #expect(snap.point(from: .zero, to: small, kind: .line, zoom: 1) == small)
        let free = NSPoint(x: 100, y: 30)
        #expect(snap.point(from: .zero, to: free, kind: .line, zoom: 1) == free)
        #expect(snap.alignment == nil)
    }
}
