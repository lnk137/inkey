import AppKit
import Testing
@testable import Inkey

@Suite("Anchored text boxes", .serialized)
@MainActor
struct CenteredTextTests {
    let helper = CanvasTests()
    let none = NSRange(location: NSNotFound, length: 0)

    func expectCenter(_ rect: NSRect, _ point: NSPoint) {
        #expect(abs(rect.minX - point.x) < 0.001)
    }

    @Test func centerStaysAtCrosshairThroughoutCompositionNewlinesDeletionAndCommit() throws {
        for size in [6.0, 20, 80, 200] {
            for zoom in [0.7, 1.0, 2.0] {
                let (window, _) = helper.makeCanvas()
                let name = "InkeyTests.\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: name))
                defer { defaults.removePersistentDomain(forName: name) }
                let preferences = UserPreferences(defaults: defaults); preferences.defaultFontSize = size
                let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 820, height: 560), preferences: preferences)
                window.contentView = canvas
                canvas.draft.zoom = zoom; canvas.draft.offset = InkPoint(NSPoint(x: -50, y: 70))
                let center = NSPoint(x: 420, y: 240), worldCenter = canvas.world(center)
                canvas.beginText(at: worldCenter)
                let editor = try #require(window.firstResponder as? InlineTextView)
                let context = try #require(editor.inputContext)
                expectCenter(editor.frame, center)
                for value in ["n", "nihao", "你好"] {
                    editor.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0), replacementRange: none)
                    expectCenter(editor.frame, center)
                }
                editor.insertText("你好", replacementRange: none)
                expectCenter(editor.frame, center)
                editor.insertText("\nright", replacementRange: none)
                expectCenter(editor.frame, center)
                editor.deleteBackward(nil)
                expectCenter(editor.frame, center)
                canvas.commitText()
                let item = try #require(canvas.draft.items.first)
                #expect(item.text == "你好\nrigh")
                let savedCenter = canvas.screen(item.points[0].point)
                #expect(abs(savedCenter.x - center.x) < 0.001)
                #expect(editor.inputContext === context)
            }
        }
    }

    @Test func mouseMovementDoesNotDragTheExistingTextCenter() throws {
        let (window, canvas) = helper.makeCanvas()
        let center = NSPoint(x: 250, y: 200)
        canvas.beginText(at: center)
        let editor = try #require(window.firstResponder as? InlineTextView)
        editor.insertText("left", replacementRange: none)
        canvas.updatePointerLocation(canvas.convert(NSPoint(x: 500, y: 300), to: nil))
        expectCenter(editor.frame, center)
        #expect(!canvas.typingCaretVisible)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: none)
        expectCenter(editor.frame, center)
    }

    @Test func editingExistingDraftTextKeepsItsStoredTopLeftOrigin() throws {
        let (window, canvas) = helper.makeCanvas()
        let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 120, y: 90))], color: InkColor.light[0], text: "old", fontSize: 36)
        canvas.draft.items = [item]
        canvas.beginText(at: item.points[0].point, item: item)
        let editor = try #require(window.firstResponder as? InlineTextView)
        #expect(editor.frame.origin == item.points[0].point)
        editor.insertText(" longer", replacementRange: none)
        #expect(editor.frame.origin == item.points[0].point)
        canvas.commitText()
        #expect(canvas.draft.items.first?.points == item.points)
        #expect(canvas.draft.items.first?.id == item.id)
    }
}
