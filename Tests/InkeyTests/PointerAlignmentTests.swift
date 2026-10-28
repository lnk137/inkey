import AppKit
import Testing
@testable import Inkey

@Suite("Event-based pointer alignment", .serialized)
@MainActor
struct PointerAlignmentTests {
    let helper = CanvasTests()

    @Test func firstNativeInputUsesTheLastCrosshairEventWithoutResamplingTheMouse() throws {
        try PointerInputTests().withPointerMode {
            for zoom in [0.7, 1.0, 2.0] {
                let (window, canvas) = helper.makeCanvas()
                canvas.draft.zoom = zoom; canvas.draft.offset = InkPoint(NSPoint(x: -70, y: 55))
                let hotspot = NSPoint(x: 430, y: 260)
                let location = canvas.convert(hotspot, to: nil)
                canvas.mouseMoved(with: helper.mouse(.mouseMoved, location, window: window))
                let editor = try #require(window.firstResponder as? InlineTextView)
                editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                #expect(editor.frame.minX == hotspot.x)
                editor.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
                #expect(editor.frame.minX == hotspot.x)
                canvas.commitText()
                let item = try #require(canvas.draft.items.first)
                let origin = canvas.screen(item.points[0].point)
                #expect(abs(origin.x - hotspot.x) < 0.001)
            }
        }
    }

    @Test func clickLocationRemainsTheAnchorEvenIfGlobalPointerSamplingWouldDiffer() throws {
        try PointerInputTests().withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let hotspot = NSPoint(x: 380, y: 270), location = canvas.convert(hotspot, to: nil)
            canvas.mouseDown(with: helper.mouse(.leftMouseDown, location, window: window))
            canvas.mouseUp(with: helper.mouse(.leftMouseUp, location, window: window))
            canvas.prepareInputSession()
            let editor = try #require(window.firstResponder as? InlineTextView)
            #expect(editor.frame.minX == hotspot.x)
            editor.insertText("left", replacementRange: NSRange(location: NSNotFound, length: 0))
            canvas.commitText()
            let item = try #require(canvas.draft.items.first)
            #expect(item.bounds.minX == hotspot.x)
        }
    }
}
