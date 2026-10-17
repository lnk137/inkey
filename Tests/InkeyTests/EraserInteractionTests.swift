import Testing
import AppKit
@testable import Inkey

@Suite("Eraser interaction", .serialized)
@MainActor
struct EraserInteractionTests {
    let helper = CanvasTests()
    func p(_ x: Double, _ y: Double) -> InkPoint { InkPoint(NSPoint(x: x, y: y)) }
    func stroke() -> InkItem { InkItem(kind: .stroke, points: [p(0, 50), p(100, 50)], color: InkColor.light[0], lineWidth: 2) }
    func windowPoint(_ world: NSPoint, canvas: CanvasView) -> NSPoint { canvas.convert(canvas.screen(world), to: nil) }

    @Test func entireEraserGestureCreatesOneReversibleAction() {
        let (window, canvas) = helper.makeCanvas()
        let original = stroke(); canvas.draft.items = [original]
        canvas.setEraserEnabled(true); canvas.eraserDiameter = 24
        let start = windowPoint(NSPoint(x: 50, y: 50), canvas: canvas)
        let end = windowPoint(NSPoint(x: 80, y: 50), canvas: canvas)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        let erased = canvas.draft.items
        #expect(erased.count == 2)
        #expect(erased[0].points.last!.x == 37)
        #expect(erased[1].points.first!.x == 93)
        canvas.undo(nil); #expect(canvas.draft.items == [original])
        #expect(canvas.undoManager?.canUndo == false)
        canvas.redo(nil); #expect(canvas.draft.items == erased)
    }

    @Test func temporaryOptionEraseDoesNotLatchTool() {
        let (window, canvas) = helper.makeCanvas()
        canvas.draft.items = [stroke()]
        let point = windowPoint(NSPoint(x: 50, y: 50), canvas: canvas)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window, modifiers: .option))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, point, window: window))
        #expect(canvas.draft.items.count == 2)
        #expect(!canvas.eraserEnabled)
        let start = windowPoint(NSPoint(x: 100, y: 100), canvas: canvas)
        let end = windowPoint(NSPoint(x: 130, y: 100), canvas: canvas)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
        canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
        #expect(canvas.draft.items.count == 3)
    }

    @Test func eraserDiameterStaysConstantOnScreenAtDifferentZooms() {
        let (window, canvas) = helper.makeCanvas()
        canvas.draft.items = [stroke()]; canvas.draft.zoom = 2
        canvas.setEraserEnabled(true); canvas.eraserDiameter = 20
        let point = windowPoint(NSPoint(x: 50, y: 50), canvas: canvas)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window))
        canvas.mouseUp(with: helper.mouse(.leftMouseUp, point, window: window))
        #expect(abs(canvas.draft.items[0].points.last!.x - 44) < 0.0001)
        #expect(abs(canvas.draft.items[1].points.first!.x - 56) < 0.0001)
    }

    @Test func typingExitsEraserAndFlushFinishesInProgressErase() {
        let (window, canvas) = helper.makeCanvas()
        let original = stroke(); canvas.draft.items = [original]
        canvas.setEraserEnabled(true)
        let point = windowPoint(NSPoint(x: 50, y: 50), canvas: canvas)
        canvas.mouseDown(with: helper.mouse(.leftMouseDown, point, window: window))
        canvas.flush()
        #expect(!canvas.isDrawing)
        canvas.undo(nil); #expect(canvas.draft.items == [original])
        canvas.keyDown(with: helper.key("node", window: window))
        #expect(!canvas.eraserEnabled)
        #expect(canvas.isEditing)
    }

    @Test func paletteRestoresPresetAndCustomInkFromPreferences() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        preferences.saveInk(SavedInk(color: InkColor("586E75"), slot: 2, isPreset: false), dark: false)
        let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 350, height: 80), preferences: preferences)
        palette.paperIsDark = false; palette.refreshAppearance()
        #expect(palette.current == InkColor("586E75"))
        palette.choose(4)
        let recreated = PaletteView(frame: palette.frame, preferences: preferences)
        recreated.paperIsDark = false; recreated.refreshAppearance()
        #expect(recreated.current == recreated.colors[4])
        #expect(recreated.slot == 4)
    }

    @Test func singleEraserButtonTogglesAndRightClickOpensSizing() throws {
        let (window, canvas) = helper.makeCanvas()
        let palette = PaletteView(frame: NSRect(x: 20, y: 20, width: PaletteView.preferredWidth, height: 80))
        canvas.addSubview(palette)
        window.orderFront(nil)
        defer { palette.closePicker(accept: true); window.orderOut(nil) }
        let button = try #require(palette.subviews.compactMap { $0 as? ToolButton }.first)
        button.performClick(nil)
        #expect(palette.eraserEnabled)
        #expect(!palette.hasPopover)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        button.rightMouseDown(with: event)
        #expect(palette.eraserEnabled)
        #expect(palette.eraserPopover != nil)
        button.performClick(nil)
        #expect(!palette.eraserEnabled)
    }
}
