import Testing
import AppKit
@testable import Inkey

@Suite("Draft persistence")
struct DraftTests {
    @Test func roundTripPreservesEditableContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(directory: directory)
        var draft = Draft()
        draft.name = "two pointers"
        draft.zoom = 1.5
        draft.offset = InkPoint(NSPoint(x: -80, y: 40))
        draft.items = [
            InkItem(kind: .text, points: [InkPoint(NSPoint(x: 30, y: 40))], color: InkColor.light[2], text: "左指针 left\nright"),
            InkItem(kind: .arrow, points: [InkPoint(.zero), InkPoint(NSPoint(x: 120, y: 90))], color: InkColor.light[4]),
            InkItem(kind: .stroke, points: [InkPoint(.zero), InkPoint(NSPoint(x: 10, y: 3)), InkPoint(NSPoint(x: 20, y: 8))], color: InkColor.light[1])
        ]
        try store.save(draft)
        let url = directory.appendingPathComponent("\(draft.id).inkey")
        #expect(try store.load(url) == draft)
        #expect(store.recent().count == 1)
    }

    @Test func rejectsUnsupportedAndInvalidFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(directory: directory)
        var draft = Draft(); draft.version = 99
        try store.save(draft)
        let url = directory.appendingPathComponent("\(draft.id).inkey")
        #expect(throws: (any Error).self) { try store.load(url) }
        draft.version = 1; draft.zoom = -1
        try store.save(draft)
        #expect(throws: (any Error).self) { try store.load(url) }
        draft.zoom = 1
        draft.items = [InkItem(kind: .stroke, points: [], color: InkColor.light[0])]
        try store.save(draft)
        #expect(throws: (any Error).self) { try store.load(url) }
    }

    @Test func recentDraftsAreSortedWithoutReplacingOthers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(directory: directory)
        var older = Draft(); older.modified = Date(timeIntervalSince1970: 100)
        var newer = Draft(); newer.modified = Date(timeIntervalSince1970: 200)
        try store.save(newer); try store.save(older)
        #expect(store.recent().map { $0.1.id } == [newer.id, older.id])
    }

    @Test func hitTestingUsesStrokeGeometry() {
        let arrow = InkItem(kind: .arrow, points: [InkPoint(.zero), InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0])
        #expect(arrow.hit(NSPoint(x: 50, y: 52), tolerance: 5))
        #expect(!arrow.hit(NSPoint(x: 10, y: 90), tolerance: 5))
        var moved = arrow; moved.translate(x: 40, y: -20)
        #expect(moved.points[0] == InkPoint(NSPoint(x: 40, y: -20)))
    }

    @Test func parsesOnlyValidHexColors() {
        #expect(InkColor.parse("#C84D45") == InkColor.light[1])
        #expect(InkColor.parse(" 327bb3 ")?.hex == "#327BB3")
        #expect(InkColor.parse("xyzxyz") == nil)
        #expect(InkColor.parse("#FFF") == nil)
    }
}

@Suite("Canvas interactions", .serialized)
@MainActor
struct CanvasTests {
    func makeCanvas() -> (NSWindow, CanvasView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 820, height: 560))
        window.contentView = canvas
        return (window, canvas)
    }
    func mouse(_ type: NSEvent.EventType, _ point: NSPoint, window: NSWindow, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    func key(_ text: String, window: NSWindow, keyCode: UInt16 = 0, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: keyCode)!
    }

    @Test func drawingCommitsTextAndCreatesArrowWithoutToolSwitch() {
        let (window, canvas) = makeCanvas()
        canvas.keyDown(with: key("left", window: window))
        #expect(canvas.isEditing)
        canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 180, y: 400), window: window, modifiers: .shift))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 360, y: 400), window: window, modifiers: .shift))
        canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 360, y: 400), window: window))
        #expect(canvas.draft.items.count == 2)
        #expect(canvas.draft.items[0].text == "left")
        #expect(canvas.draft.items[1].kind == .arrow)
        #expect(!canvas.isEditing)
        canvas.keyDown(with: key("right", window: window))
        canvas.commitText()
        #expect(canvas.draft.items.last?.text == "right")
    }

    @Test func clickDoesNotCreateDotAndDragCreatesOneUndoableStroke() {
        let (window, canvas) = makeCanvas()
        canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 100, y: 100), window: window))
        #expect(canvas.draft.items.isEmpty)
        canvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100), window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 120, y: 120), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 120, y: 120), window: window))
        #expect(canvas.draft.items.count == 1)
        canvas.undo(nil); #expect(canvas.draft.items.isEmpty)
        canvas.redo(nil); #expect(canvas.draft.items.count == 1)
    }

    @Test func canceledColorPreviewRestoresObjectAndCreatesNoUndoStep() {
        let (_, canvas) = makeCanvas()
        let item = InkItem(kind: .text, points: [InkPoint(.zero)], color: InkColor.light[0], text: "node")
        canvas.draft.items = [item]; canvas.selection = item.id
        canvas.beginColorPreview()
        canvas.applyColor(InkColor.light[1]); canvas.applyColor(InkColor.light[2])
        canvas.finishColorPreview(accept: false, original: InkColor.light[0])
        #expect(canvas.draft.items[0].color == item.color)
        #expect(canvas.undoManager?.canUndo == false)
    }

    @Test func acceptedColorPreviewIsOneUndoStep() {
        let (_, canvas) = makeCanvas()
        let item = InkItem(kind: .text, points: [InkPoint(.zero)], color: InkColor.light[0], text: "node")
        canvas.draft.items = [item]; canvas.selection = item.id
        canvas.beginColorPreview()
        canvas.applyColor(InkColor.light[1]); canvas.applyColor(InkColor.light[2])
        canvas.finishColorPreview(accept: true, original: InkColor.light[0])
        #expect(canvas.draft.items[0].color == InkColor.light[2])
        canvas.undo(nil); #expect(canvas.draft.items[0].color == item.color)
        #expect(canvas.undoManager?.canUndo == false)
    }

    @Test func colorChangeDuringTextEditingPreservesTextAndChangesWholeVariable() {
        let (window, canvas) = makeCanvas()
        canvas.keyDown(with: key("variable", window: window))
        canvas.applyColor(InkColor.light[4])
        #expect(canvas.isEditing)
        canvas.commitText()
        #expect(canvas.draft.items[0].text == "variable")
        #expect(canvas.draft.items[0].color == InkColor.light[4])
    }

    @Test func worldScreenConversionRoundTrips() {
        let (_, canvas) = makeCanvas()
        canvas.draft.zoom = 1.7
        canvas.draft.offset = InkPoint(NSPoint(x: -80, y: 120))
        let p = NSPoint(x: 240, y: 340)
        let result = canvas.world(canvas.screen(p))
        #expect(abs(result.x - p.x) < 0.0001)
        #expect(abs(result.y - p.y) < 0.0001)
    }

    @Test func exportsContentWithBackgroundAsPNGAndPDF() throws {
        let (_, canvas) = makeCanvas()
        canvas.draft.items = [InkItem(kind: .text, points: [InkPoint(NSPoint(x: -200, y: -300))], color: InkColor.light[0], text: "left → right")]
        let png = try #require(canvas.exportData(pdf: false))
        #expect(Array(png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
        let pdf = try #require(canvas.exportData(pdf: true))
        #expect(String(data: pdf.prefix(4), encoding: .ascii) == "%PDF")
    }
}
