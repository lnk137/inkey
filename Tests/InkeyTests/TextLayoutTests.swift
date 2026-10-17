import AppKit
import Testing
@testable import Inkey

@Suite("Stable mixed-script text layout", .serialized)
@MainActor
struct TextLayoutTests {
    let helper = CanvasTests()
    let none = NSRange(location: NSNotFound, length: 0)

    @Test func pinyinAndCJKKeepTheSameBaselineThroughoutCompositionAndCommit() throws {
        for size in [12.0, 20, 48] {
            let (_, canvas) = helper.makeCanvas()
            let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], fontSize: size)
            canvas.beginText(at: item.points[0].point, item: item)
            let text = try #require(canvas.subviews.compactMap { $0 as? InlineTextView }.first)
            let manager = try #require(text.layoutManager)
            let container = try #require(text.textContainer)
            let context = try #require(text.inputContext)
            var baseline: CGFloat?
            for value in ["n", "ni", "你", "你好", "nihao"] {
                text.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0), replacementRange: none)
                manager.ensureLayout(for: container)
                let y = manager.location(forGlyphAt: 0).y
                if let baseline { #expect(abs(y - baseline) < 0.001) }
                else { baseline = y }
                #expect(text.frame.origin == NSPoint(x: 100, y: 100))
                #expect(text.textContainerOrigin == .zero)
                #expect(manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height == InkTypography.lineHeight(size))
            }
            text.insertText("你好", replacementRange: none)
            manager.ensureLayout(for: container)
            #expect(manager.location(forGlyphAt: 0).y == baseline)
            let liveSize = text.frame.size
            let (storage, committed, committedContainer) = InkTypography.layout("你好", size: size, color: item.color)
            committed.ensureLayout(for: committedContainer)
            #expect(committed.location(forGlyphAt: 0).y == baseline)
            #expect(InkTypography.size("你好", fontSize: size) == liveSize)
            #expect(storage.string == "你好")
            #expect(text.inputContext === context)
            canvas.commitText()
            #expect(canvas.draft.items.last?.text == "你好")
            #expect(canvas.draft.items.last?.fontSize == size)
        }
    }

    @Test func multilineLatinAndCJKUseTheSameLineSpacingAtDifferentZooms() throws {
        for zoom in [0.7, 1.0, 2.0] {
            let (_, canvas) = helper.makeCanvas()
            canvas.draft.zoom = zoom
            canvas.beginText(at: NSPoint(x: 100, y: 100))
            let text = try #require(canvas.subviews.compactMap { $0 as? InlineTextView }.first)
            text.insertText("left\n你好\nright", replacementRange: none)
            let manager = try #require(text.layoutManager), container = try #require(text.textContainer)
            manager.ensureLayout(for: container)
            var baselines: [CGFloat] = []
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, range, _ in
                baselines.append(rect.minY + manager.location(forGlyphAt: range.location).y)
            }
            #expect(baselines.count == 3)
            #expect(abs(baselines[1] - baselines[0] - InkTypography.lineHeight(20 * zoom)) < 0.001)
            #expect(abs(baselines[2] - baselines[1] - InkTypography.lineHeight(20 * zoom)) < 0.001)
        }
    }
}
