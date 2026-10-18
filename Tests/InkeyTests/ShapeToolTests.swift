import AppKit
import Testing
@testable import Inkey

@Suite("Shape tools and editable presets", .serialized)
@MainActor
struct ShapeToolTests {
    let helper = CanvasTests()

    @Test func shiftShapesDrawInBothDirectionsAndUndoAsOneGesture() {
        for shape in ShiftShape.allCases {
            for delta in [NSPoint(x: 130, y: 70), NSPoint(x: -130, y: -70), NSPoint(x: -130, y: 70), NSPoint(x: 130, y: -70)] {
                let (window, canvas) = helper.makeCanvas()
                canvas.shiftShape = shape
                let start = NSPoint(x: 250, y: 250)
                let end = NSPoint(x: start.x + delta.x, y: start.y + delta.y)
                canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window, modifiers: .shift))
                canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window, modifiers: .shift))
                canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
                #expect(canvas.draft.items.count == 1)
                let item = canvas.draft.items[0]
                #expect(item.kind == shape.kind)
                if shape == .rectangle {
                    #expect(abs(item.bounds.width - abs(delta.x) - item.lineWidth) < 0.001)
                    #expect(abs(item.bounds.height - abs(delta.y) - item.lineWidth) < 0.001)
                }
                canvas.undo(nil); #expect(canvas.draft.items.isEmpty)
                canvas.redo(nil); #expect(canvas.draft.items == [item])
                // A chosen Shift tool never changes ordinary freehand drawing.
                canvas.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
                canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
                canvas.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
                #expect(canvas.draft.items.last?.kind == .stroke)
            }
        }
    }

    @Test func shapesPersistExportAndEraseOnlyTheirOutline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DraftStore(directory: directory)
        let (_, canvas) = helper.makeCanvas()
        for shape in [ShiftShape.line, .rectangle, .ellipse] {
            let item = InkItem(kind: shape.kind, points: [InkPoint(.zero), InkPoint(NSPoint(x: 100, y: 80))], color: InkColor.light[0])
            canvas.draft.items = [item]
            try store.save(canvas.draft)
            #expect(try store.load(directory.appendingPathComponent("\(canvas.draft.id).inkey")) == canvas.draft)
            #expect(canvas.exportData(pdf: false) != nil)
            #expect(canvas.exportData(pdf: true) != nil)
            let edge = item.outline[item.outline.count / 2]
            #expect(InkEraser.erase([item], from: edge, to: edge, radius: 5) != [item])
            if shape != .line {
                let middle = InkPoint(NSPoint(x: 50, y: 40))
                #expect(!item.hit(middle.point, tolerance: 5))
                #expect(InkEraser.erase([item], from: middle, to: middle, radius: 5) == [item])
            }
        }
    }

    @Test func shortcutsUsePhysicalNumberKeysAndShapeChoicePersists() throws {
        let (_, windowCanvas) = helper.makeCanvas()
        let window = try #require(windowCanvas.window)
        for (index, code) in [UInt16(18), 19, 20, 21].enumerated() {
            #expect(ShiftShape.shortcut(helper.key("!", window: window, keyCode: code, modifiers: .shift)) == ShiftShape.allCases[index])
            #expect(ShiftShape.shortcut(helper.key("1", window: window, keyCode: code)) == nil)
        }
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 320, height: 80), preferences: preferences)
        var chosen: ShiftShape?
        palette.onShape = { chosen = $0 }
        palette.chooseShape(.ellipse)
        #expect(chosen == .ellipse)
        #expect(UserPreferences(defaults: defaults).shiftShape == .ellipse)
    }

    @Test func oldSquareDraftsKeepTheirGeometryAndToolPreferenceSelectsRectangle() throws {
        let old = InkItem(kind: .square, points: [InkPoint(.zero), InkPoint(NSPoint(x: 130, y: 70))], color: InkColor.light[0])
        let decoded = try JSONDecoder().decode(InkItem.self, from: JSONEncoder().encode(old))
        #expect(decoded.kind == .square)
        #expect(decoded.bounds.width == decoded.bounds.height)
        #expect(decoded.outline[2] == InkPoint(NSPoint(x: 130, y: 130)))
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("square", forKey: "shiftShape")
        let preferences = UserPreferences(defaults: defaults)
        #expect(preferences.shiftShape == .rectangle)
        preferences.shiftShape = .rectangle
        #expect(UserPreferences(defaults: defaults).shiftShape == .rectangle)
    }

    @Test func rightClickColorMenuAndAcceptedOrCanceledEdits() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let (window, canvas) = helper.makeCanvas()
        let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 320, height: 80), preferences: UserPreferences(defaults: defaults))
        palette.paperIsDark = false; palette.refreshAppearance()
        canvas.addSubview(palette); window.orderFront(nil)
        defer { palette.closePicker(accept: false); window.orderOut(nil) }
        let swatch = try #require(palette.subviews.compactMap { $0 as? SwatchButton }.first)
        let menu = try #require(swatch.menu(for: helper.mouse(.rightMouseDown, .zero, window: window)))
        #expect(menu.items.map(\.title) == ["编辑颜色…", "删除颜色"])
        let original = palette.colors[0]
        palette.editPreset(0)
        palette.popover?.behavior = .applicationDefined
        let canceled = try #require(palette.popover?.contentViewController as? ColorPanelController)
        canceled.update(InkColor("123456"), syncSquare: true)
        palette.closePicker(accept: false)
        #expect(palette.colors[0] == original)
        #expect(palette.current == original)
        palette.editPreset(0)
        palette.popover?.behavior = .applicationDefined
        let accepted = try #require(palette.popover?.contentViewController as? ColorPanelController)
        accepted.update(InkColor("ABCDEF"), syncSquare: true)
        accepted.done()
        #expect(palette.colors[0] == InkColor("ABCDEF"))
        #expect(defaults.stringArray(forKey: "lightPresets")?.first == "#ABCDEF")
    }

    @Test func presetsCanBeEditedDeletedToEmptyAndAddedAfterRestart() throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 320, height: 80), preferences: preferences)
        palette.paperIsDark = false; palette.refreshAppearance()
        palette.choose(2); palette.replacePreset(InkColor("123456"))
        #expect(palette.colors[2].hex == "#123456")
        palette.deletePreset(1)
        #expect(palette.colors.count == 5)
        #expect(palette.slot == 1)
        while !palette.colors.isEmpty { palette.deletePreset(0) }
        let restored = PaletteView(frame: palette.frame, preferences: preferences)
        restored.paperIsDark = false; restored.refreshAppearance()
        #expect(restored.colors.isEmpty)
        restored.choose(5) // Removed shortcuts are harmless.
        restored.addPreset(InkColor("ABCDEF"))
        restored.refreshAppearance()
        #expect(restored.colors == [InkColor("ABCDEF")])
        #expect(restored.current == InkColor("ABCDEF"))
        restored.paperIsDark = true; restored.refreshAppearance()
        #expect(restored.colors == InkColor.dark)
        restored.resetPresets()
        restored.paperIsDark = false; restored.refreshAppearance()
        #expect(restored.colors == InkColor.light)
    }
}
