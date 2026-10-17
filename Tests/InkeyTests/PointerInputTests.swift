import AppKit
import Testing
@testable import Inkey

@Suite("Pointer-led typing", .serialized)
@MainActor
struct PointerInputTests {
    let helper = CanvasTests()
    func withPointerMode(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "pointerPlacement")
        defaults.set(true, forKey: "pointerPlacement")
        defer {
            if let old { defaults.set(old, forKey: "pointerPlacement") }
            else { defaults.removeObject(forKey: "pointerPlacement") }
        }
        try body()
    }
    func setup(_ canvas: CanvasView) -> InlineTextView {
        let initial = canvas.convert(NSPoint(x: 100, y: 100), to: nil)
        canvas.updatePointerLocation(initial)
        canvas.beginText(at: NSPoint(x: 103, y: 104))
        let text = canvas.subviews.compactMap { $0 as? InlineTextView }.first!
        text.insertText("left", replacementRange: NSRange(location: 0, length: 0))
        return text
    }

    @Test func movingThenTypingCreatesAnotherVariableWithoutClicking() {
        withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let original = setup(canvas)
            let target = canvas.convert(NSPoint(x: 400, y: 250), to: nil)
            canvas.updatePointerLocation(target)
            #expect(canvas.draft.items.isEmpty) // Hover alone never commits text.
            #expect(original.insertionPointColor == .clear)
            #expect(canvas.retargetTypingIfNeeded(helper.key("right", window: window), from: original, at: target))
            canvas.commitText()
            #expect(canvas.draft.items.map(\.text) == ["left", "right"])
            #expect(canvas.draft.items[1].points[0] == InkPoint(NSPoint(x: 403, y: 254)))
        }
    }

    @Test func smallPointerJitterDoesNotSplitVariable() {
        withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let text = setup(canvas)
            let target = canvas.convert(NSPoint(x: 105, y: 102), to: nil)
            #expect(!canvas.retargetTypingIfNeeded(helper.key("x", window: window), from: text, at: target))
            #expect(canvas.isEditing)
            #expect(canvas.draft.items.isEmpty)
        }
    }

    @Test func backspaceKeepsCurrentTextEvenAfterPointerMoves() {
        withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let text = setup(canvas)
            let target = canvas.convert(NSPoint(x: 400, y: 250), to: nil)
            canvas.updatePointerLocation(target)
            canvas.keepCurrentTextForCorrection(at: target)
            text.deleteBackward(nil)
            #expect(!canvas.retargetTypingIfNeeded(helper.key("t", window: window), from: text, at: target))
            text.acceptRoutedKey(helper.key("t", window: window))
            canvas.commitText()
            #expect(canvas.draft.items.count == 1)
            #expect(canvas.draft.items[0].text == "left")
        }
    }

    @Test func preciseEditingAndMarkedTextStayAtTheirOriginalLocation() {
        withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let text = setup(canvas)
            let target = canvas.convert(NSPoint(x: 400, y: 250), to: nil)
            text.setMarkedText("指针", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(!canvas.retargetTypingIfNeeded(helper.key("x", window: window), from: text, at: target))
            #expect(text.hasMarkedText())
            text.unmarkText()
            canvas.promoteTextEditing()
            #expect(!canvas.retargetTypingIfNeeded(helper.key("x", window: window), from: text, at: target))
            #expect(canvas.draft.items.isEmpty)
        }
    }

    @Test func pointerOverPaletteDoesNotRelocateInput() {
        withPointerMode {
            let (window, canvas) = helper.makeCanvas()
            let text = setup(canvas)
            canvas.isCanvasLocation = { _ in false }
            let target = canvas.convert(NSPoint(x: 400, y: 250), to: nil)
            #expect(!canvas.retargetTypingIfNeeded(helper.key("x", window: window), from: text, at: target))
            #expect(text.insertionPointColor != .clear)
        }
    }

    @Test func turningOffTrailPreservesTextAndDocument() {
        withPointerMode {
            let (_, canvas) = helper.makeCanvas()
            let text = setup(canvas)
            let snapshot = canvas.draft
            for x in stride(from: 130.0, through: 230.0, by: 10) {
                canvas.updatePointerLocation(canvas.convert(NSPoint(x: x, y: 200), to: nil))
            }
            canvas.cursorTrailEnabled = false
            #expect(canvas.draft == snapshot)
            #expect(text.string == "left")
            #expect(canvas.isEditing)
        }
    }
}
