import AppKit
import Testing
@testable import Inkey

@Suite("Canvas clipboard", .serialized)
@MainActor
struct ClipboardTests {
    let helper = CanvasTests()

    @Test func textPasteUsesPointerCenterAndConfiguredFontWithOneUndo() throws {
        let (window, canvas) = helper.makeCanvas()
        let previousSize = canvas.preferences.defaultFontSize
        defer { canvas.preferences.defaultFontSize = previousSize }
        canvas.preferences.defaultFontSize = 32
        canvas.draft.zoom = 1.7
        canvas.draft.offset = InkPoint(NSPoint(x: 25, y: -18))
        let point = NSPoint(x: 350, y: 240)
        canvas.updatePointerLocation(canvas.convert(point, to: nil))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("你好\nclipboard", forType: .string)
        canvas.pasteContents(from: board)
        let item = try #require(canvas.draft.items.first)
        #expect(item.text == "你好\nclipboard")
        #expect(item.fontSize == 32)
        #expect(abs(canvas.screen(NSPoint(x: item.bounds.midX, y: item.bounds.midY)).x - point.x) < 0.001)
        #expect(abs(canvas.screen(NSPoint(x: item.bounds.midX, y: item.bounds.midY)).y - point.y) < 0.001)
        #expect(window.firstResponder is InlineTextView)
        canvas.undo(nil)
        #expect(canvas.draft.items.isEmpty && canvas.undoManager?.canUndo == false)
        canvas.redo(nil)
        #expect(canvas.draft.items == [item])
    }

    @Test func imagePasteFitsVisibleCanvasAndPreservesAspectRatio() throws {
        for zoom in [0.5, 1.0, 2.0] {
            let (_, canvas) = helper.makeCanvas()
            canvas.draft.zoom = zoom
            let point = NSPoint(x: 340, y: 260)
            canvas.updatePointerLocation(canvas.convert(point, to: nil))
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let image = NSImage(size: NSSize(width: 1600, height: 900), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
            board.writeObjects([image])
            canvas.pasteContents(from: board)
            let item = try #require(canvas.draft.items.first)
            #expect(item.kind == .image && item.imageData != nil)
            #expect(abs(item.imageWidth / item.imageHeight - 1600.0 / 900) < 0.001)
            #expect(item.imageWidth * zoom <= canvas.bounds.width * 0.6 + 0.001)
            #expect(item.imageHeight * zoom <= canvas.bounds.height * 0.6 + 0.001)
            let center = canvas.screen(NSPoint(x: item.bounds.midX, y: item.bounds.midY))
            #expect(hypot(center.x - point.x, center.y - point.y) < 0.001)
            canvas.undo(nil)
            #expect(canvas.draft.items.isEmpty)
        }
    }
}
