import AppKit
import Testing
@testable import Inkey

@Suite("Text editor to canvas handoff", .serialized)
@MainActor
struct TextHandoffTests {
    let helper = CanvasTests()
    let none = NSRange(location: NSNotFound, length: 0)

    func pixels(_ canvas: CanvasView, in rect: NSRect) throws -> [UInt8] {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: rect))
        canvas.cacheDisplay(in: rect, to: bitmap)
        let data = try #require(bitmap.bitmapData)
        let width = bitmap.pixelsWide * bitmap.bitsPerPixel / 8
        return (0..<bitmap.pixelsHigh).flatMap { row in
            Array(UnsafeBufferPointer(start: data + row * bitmap.bytesPerRow, count: width))
        }
    }

    @Test func startingAtBPreservesTheLayoutAndAppearanceOfA() throws {
        try PointerInputTests().withPointerMode {
            try TextResizeTests().withPreferences { preferences in
                for (size, zoom) in [12.0, 20, 48].flatMap({ size in [0.7, 1.0, 1.3, 1.7, 2.0].map { (size, $0) } }) {
                    preferences.defaultFontSize = size
                    let (window, canvas) = TextResizeTests().makeCanvas(preferences)
                    canvas.cursorTrailEnabled = false
                    canvas.draft.zoom = zoom
                    canvas.draft.offset = InkPoint(NSPoint(x: -30, y: 15))
                    let a = NSPoint(x: 220, y: 140), b = NSPoint(x: 620, y: 400)
                    canvas.updatePointerLocation(canvas.convert(a, to: nil))
                    canvas.beginText(at: canvas.world(a))
                    let editor = try #require(window.firstResponder as? InlineTextView)
                    editor.insertText("left你好\nright", replacementRange: none)
                    canvas.updatePointerLocation(canvas.convert(b, to: nil))
                    let context = editor.inputContext
                    let crop = NSRect(x: 40, y: 40, width: 360, height: 200)
                    // Capturing also forces AppKit to create the editor's backing layer.
                    let before = try pixels(canvas, in: crop)
                    let frame = editor.frame
                    let manager = try #require(editor.layoutManager)
                    let positions = (0..<manager.numberOfGlyphs).map { manager.location(forGlyphAt: $0) }
                    #expect(canvas.retargetTypingIfNeeded(helper.key("b", window: window), from: editor, at: canvas.convert(b, to: nil)))
                    let after = try pixels(canvas, in: crop)
                    let item = try #require(canvas.draft.items.first)
                    let (storage, saved, container) = InkTypography.layout(item.text, size: item.fontSize, color: item.color)
                    defer { _ = storage }
                    saved.ensureLayout(for: container)
                    #expect(positions == (0..<saved.numberOfGlyphs).map { saved.location(forGlyphAt: $0) })
                    let origin = canvas.screen(item.bounds.origin)
                    #expect(hypot(frame.minX - origin.x, frame.minY - origin.y) < 0.001)
                    #expect(abs(frame.width - item.bounds.width * zoom) < 0.001)
                    #expect(abs(frame.height - item.bounds.height * zoom) < 0.001)
                    #expect(before.count == after.count)
                    // Independent view transforms can differ slightly in edge antialiasing.
                    // A displaced glyph produces substantially more error than this bound.
                    let error = zip(before, after).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(before.count)
                    #expect(error < 0.05, "A changed while starting B at zoom \(zoom): mean pixel error \(error)")
                    #expect(window.firstResponder === editor && editor.inputContext === context)
                }
            }
        }
    }
}
