import Testing
import AppKit
@testable import Inkey

@Suite("Vector eraser")
struct ErasingTests {
    func p(_ x: Double, _ y: Double) -> InkPoint { InkPoint(NSPoint(x: x, y: y)) }
    func stroke() -> InkItem { InkItem(kind: .stroke, points: [p(0, 50), p(100, 50)], color: InkColor.light[0], lineWidth: 2) }

    @Test func cutsMiddleOfSegmentWithoutDeletingWholeStroke() {
        let original = stroke()
        let result = InkEraser.erase([original], from: p(50, 50), to: p(50, 50), radius: 9)
        #expect(result.count == 2)
        #expect(result[0].points == [p(0, 50), p(40, 50)])
        #expect(result[1].points == [p(60, 50), p(100, 50)])
        #expect(result[0].id == original.id)
        #expect(result[1].id != original.id)
    }

    @Test func fastSweptGestureDoesNotSkipInkBetweenEvents() {
        let result = InkEraser.erase([stroke()], from: p(50, 0), to: p(50, 100), radius: 9)
        #expect(result.count == 2)
        #expect(abs(result[0].points.last!.x - 40) < 0.0001)
        #expect(abs(result[1].points.first!.x - 60) < 0.0001)
    }

    @Test func distantEraserPreservesIdentityAndGeometry() {
        let item = stroke()
        #expect(InkEraser.erase([item], from: p(200, 0), to: p(200, 100), radius: 10) == [item])
    }

    @Test func largeEraserRemovesStrokeAndRepeatedCutsStayEditable() {
        #expect(InkEraser.erase([stroke()], from: p(50, 50), to: p(50, 50), radius: 100).isEmpty)
        let cut = InkEraser.erase([stroke()], from: p(50, 50), to: p(50, 50), radius: 9)
        let result = InkEraser.erase(cut, from: p(20, 50), to: p(20, 50), radius: 4)
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.kind == .stroke && $0.points.count >= 2 })
    }

    @Test func textAndArrowsEraseAsObjectsWhileReferencesAreProtected() {
        let text = InkItem(kind: .text, points: [p(20, 40)], color: InkColor.light[0], text: "node")
        let arrow = InkItem(kind: .arrow, points: [p(0, 50), p(100, 50)], color: InkColor.light[4])
        let image = InkItem(kind: .image, points: [p(0, 0)], color: InkColor.light[0], imageWidth: 100, imageHeight: 100)
        let result = InkEraser.erase([image, text, arrow], from: p(30, 0), to: p(30, 100), radius: 4)
        #expect(result == [image])
    }

    @Test func handlesDegenerateAndDiagonalSegments() {
        let dot = InkItem(kind: .stroke, points: [p(50, 50), p(50, 50)], color: InkColor.light[0])
        #expect(InkEraser.erase([dot], from: p(50, 50), to: p(50, 50), radius: 5).isEmpty)
        let diagonal = InkItem(kind: .stroke, points: [p(0, 0), p(100, 100)], color: InkColor.light[0])
        let result = InkEraser.erase([diagonal], from: p(0, 100), to: p(100, 0), radius: 5)
        #expect(result.count == 2)
    }
}
