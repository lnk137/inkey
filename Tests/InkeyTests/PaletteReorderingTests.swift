import AppKit
import Testing
@testable import Inkey

@Suite("Palette drag ordering", .serialized)
@MainActor
struct PaletteReorderingTests {
    func withPalette(_ body: (PaletteView, UserPreferences) throws -> Void) throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferences(defaults: defaults)
        let palette = PaletteView(frame: NSRect(x: 0, y: 0, width: 320, height: 80), preferences: preferences)
        palette.paperIsDark = false; palette.refreshAppearance()
        try body(palette, preferences)
    }

    @Test func shapeOrderPersistsAndShortcutsFollowPositionsWithoutChangingSelection() throws {
        try withPalette { palette, preferences in
            palette.chooseShape(.rectangle)
            palette.moveShape(from: 2, to: 0)
            #expect(preferences.shapeOrder == [.rectangle, .arrow, .line, .ellipse])
            #expect(preferences.shiftShape == .rectangle)
            let restored = PaletteView(frame: palette.frame, preferences: preferences)
            let buttons = restored.subviews.compactMap { $0 as? ToolButton }.filter { $0.reorderGroup == "shapes" }
            let (window, _) = CanvasTests().makeCanvas()
            for (index, code) in [UInt16(18), 19, 20, 21].enumerated() {
                let event = CanvasTests().key("!", window: window, keyCode: code, modifiers: .shift)
                #expect(ShiftShape.shortcut(event, order: preferences.shapeOrder) == preferences.shapeOrder[index])
                #expect(buttons[index].toolTip?.contains("⇧\(index + 1)") == true)
                #expect(buttons[index].toolTip?.contains(preferences.shapeOrder[index].label) == true)
                buttons[index].performClick(nil)
                #expect(preferences.shiftShape == preferences.shapeOrder[index])
            }
            palette.moveShape(from: 0, to: 3)
            #expect(preferences.shapeOrder == [.arrow, .line, .ellipse, .rectangle])
        }
    }

    @Test func colorsMoveBothDirectionsKeepCurrentInkAndRestoreSelectedSlot() throws {
        try withPalette { palette, preferences in
            let original = palette.colors
            palette.choose(2)
            var colorChanges = 0
            palette.onColor = { _ in colorChanges += 1 }
            palette.moveColor(from: 2, to: 0)
            #expect(palette.colors == [original[2], original[0], original[1]] + Array(original[3...]))
            #expect(palette.current == original[2] && palette.slot == 0)
            #expect(colorChanges == 0)
            palette.moveColor(from: 0, to: 5)
            #expect(palette.current == original[2] && palette.slot == 5)
            let restored = PaletteView(frame: palette.frame, preferences: preferences)
            restored.paperIsDark = false; restored.refreshAppearance()
            #expect(restored.colors == palette.colors)
            #expect(restored.current == original[2] && restored.slot == 5)
            restored.choose(0)
            #expect(restored.current == original[0])
            restored.paperIsDark = true; restored.refreshAppearance()
            #expect(restored.colors == InkColor.dark)
            restored.paperIsDark = false; restored.refreshAppearance()
            #expect(restored.colors == palette.colors)
        }
    }

    @Test func customInkAndRememberedReplacementSlotSurviveReordering() throws {
        try withPalette { palette, preferences in
            palette.choose(1)
            palette.current = InkColor("123456")
            palette.moveColor(from: 0, to: 4)
            #expect(palette.slot == 0 && palette.current == InkColor("123456"))
            #expect(preferences.ink(dark: false)?.isPreset == false)
            #expect(preferences.ink(dark: false)?.slot == 0)
            let before = palette.colors
            palette.moveColor(from: -1, to: 0)
            palette.moveColor(from: 0, to: 6)
            palette.moveColor(from: 0, to: 0)
            #expect(palette.colors == before)
            while !palette.colors.isEmpty { palette.deletePreset(0) }
            palette.moveColor(from: 0, to: 1)
            #expect(palette.colors.isEmpty)
        }
    }

    @Test func dropTargetsStayWithinTheirOwnRowAndRejectHiddenOrForeignButtons() throws {
        try withPalette { palette, preferences in
            let colors = palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" }
            let shapes = palette.subviews.compactMap { $0 as? ToolButton }.filter { $0.reorderGroup == "shapes" }
            @MainActor func center(_ view: NSView) -> NSPoint { NSPoint(x: view.frame.midX, y: view.frame.midY) }
            #expect(palette.reorderDestination(for: colors[0], at: center(colors[3])) === colors[3])
            #expect(palette.reorderDestination(for: shapes[0], at: center(shapes[2])) === shapes[2])
            #expect(palette.reorderDestination(for: colors[0], at: center(shapes[0])) == nil)
            #expect(palette.reorderDestination(for: shapes[0], at: center(colors[0])) == nil)
            let foreign = PaletteView(frame: palette.frame, preferences: preferences)
            #expect(foreign.reorderDestination(for: colors[0], at: center(colors[1])) == nil)
            palette.deletePreset(5)
            #expect(palette.reorderDestination(for: colors[0], at: center(colors[5])) == nil)
            palette.toggleCollapsed()
            #expect(palette.reorderDestination(for: shapes[0], at: center(shapes[1])) == nil)
        }
    }

    @Test func malformedSavedShapeOrderIsRepairedWithoutLosingTools() throws {
        try withPalette { _, preferences in
            preferences.defaults.set(["ellipse", "ellipse", "unknown", "square"], forKey: "shapeOrder")
            #expect(preferences.shapeOrder == [.ellipse, .rectangle, .arrow, .line])
        }
    }

    @Test func dragPreviewsImmediatelyAndPersistsOnlyOnRelease() throws {
        try withPalette { palette, preferences in
            let shapes = palette.subviews.compactMap { $0 as? ToolButton }.filter { $0.reorderGroup == "shapes" }
            let start = NSPoint(x: shapes[2].frame.midX, y: shapes[2].frame.midY)
            let target = NSPoint(x: shapes[0].frame.midX, y: shapes[0].frame.midY)
            palette.beginReordering(shapes[2], at: start)
            palette.updateReordering(at: NSPoint(x: start.x - 9, y: start.y))
            #expect(abs(shapes[2].frame.midX - start.x + 9) < 0.01)
            palette.updateReordering(at: target)
            #expect(abs(shapes[2].frame.midX - target.x) < 0.01)
            #expect(preferences.defaults.object(forKey: "shapeOrder") == nil)
            palette.endReordering(at: target)
            #expect(preferences.shapeOrder == [.rectangle, .arrow, .line, .ellipse])
            #expect(shapes[2].tag == 0 && shapes[0].tag == 1)
            #expect(shapes[2].alphaValue == 1)
        }
    }

    @Test func cancelledDragRestoresFramesAndColorActionsFollowNewSlots() throws {
        try withPalette { palette, _ in
            let colors = palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" }
            let frames = colors.map(\.frame)
            let original = palette.colors
            let start = NSPoint(x: colors[0].frame.midX, y: colors[0].frame.midY)
            let target = NSPoint(x: colors[3].frame.midX, y: colors[3].frame.midY)
            palette.beginReordering(colors[0], at: start)
            palette.updateReordering(at: target)
            #expect(palette.colors == original)
            palette.endReordering(at: NSPoint(x: target.x, y: 120))
            #expect(colors.map(\.frame) == frames)
            #expect(palette.colors == original)
            palette.beginReordering(colors[0], at: start)
            palette.endReordering(at: target)
            #expect(colors[0].tag == 3)
            colors[0].performClick(nil)
            #expect(palette.current == original[0] && palette.slot == 3)
            colors[0].onDelete?()
            #expect(!palette.colors.contains(original[0]))
            #expect(palette.colors == Array(original.dropFirst()))
        }
    }

    @Test func mouseGestureDistinguishesClickJitterFromReordering() throws {
        try withPalette { palette, preferences in
            let helper = CanvasTests()
            let (window, canvas) = helper.makeCanvas()
            canvas.addSubview(palette)
            let shapes = palette.subviews.compactMap { $0 as? ToolButton }.filter { $0.reorderGroup == "shapes" }
            let source = shapes[2]
            let start = palette.convert(NSPoint(x: source.frame.midX, y: source.frame.midY), to: nil)
            source.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            source.mouseDragged(with: helper.mouse(.leftMouseDragged, NSPoint(x: start.x + 2, y: start.y), window: window))
            source.mouseUp(with: helper.mouse(.leftMouseUp, start, window: window))
            #expect(preferences.shiftShape == .rectangle)
            #expect(preferences.shapeOrder == ShiftShape.allCases)
            let destination = palette.convert(NSPoint(x: shapes[0].frame.midX, y: shapes[0].frame.midY), to: nil)
            source.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            source.mouseDragged(with: helper.mouse(.leftMouseDragged, destination, window: window))
            #expect(preferences.shapeOrder == ShiftShape.allCases)
            source.mouseUp(with: helper.mouse(.leftMouseUp, destination, window: window))
            #expect(preferences.shapeOrder == [.rectangle, .arrow, .line, .ellipse])
            #expect(preferences.shiftShape == .rectangle)
        }
    }

    @Test func refreshingDuringPreviewRestoresIdentityAndCancelsPendingMouseUp() throws {
        try withPalette { palette, preferences in
            let colors = palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" }
            let original = palette.colors
            let start = NSPoint(x: colors[0].frame.midX, y: colors[0].frame.midY)
            let target = NSPoint(x: colors[4].frame.midX, y: colors[4].frame.midY)
            for action in [0, 1, 2, 3] {
                palette.beginReordering(colors[0], at: start)
                palette.updateReordering(at: target)
                switch action {
                case 0: palette.refreshAppearance()
                case 1: palette.choose(3)
                case 2: palette.toggleCollapsed(); palette.toggleCollapsed()
                default: palette.setToolbarHidden(true); palette.setToolbarHidden(false)
                }
                palette.endReordering(at: target)
                #expect(palette.colors == original)
                #expect(colors.enumerated().allSatisfy { $0.element.inkColor == original[$0.offset] && $0.element.tag == $0.offset })
                #expect(colors.allSatisfy { $0.alphaValue == 1 && ($0.layer?.animationKeys() ?? []).isEmpty })
            }
            #expect(preferences.defaults.stringArray(forKey: "lightPresets") == nil)
        }
    }

    @Test func rapidReversalsCancelWithoutDelayedFrameChanges() throws {
        try withPalette { palette, _ in
            let shapes = palette.subviews.compactMap { $0 as? ToolButton }.filter { $0.reorderGroup == "shapes" }
            let original = shapes.map(\.frame)
            let start = NSPoint(x: shapes[0].frame.midX, y: shapes[0].frame.midY)
            palette.beginReordering(shapes[0], at: start)
            for x in [213.0, 140, 212, 115, 211, 109] { palette.updateReordering(at: NSPoint(x: x, y: start.y)) }
            #expect(palette.cancelActiveGesture())
            #expect(shapes.map(\.frame) == original)
            #expect(shapes.allSatisfy { ($0.layer?.animationKeys() ?? []).isEmpty })
            #expect(!palette.cancelActiveGesture())
        }
    }

    @Test func windowClampingRestoresPreferredLocationAndRejectsCorruptPreferences() throws {
        try withPalette { palette, preferences in
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
            container.addSubview(palette)
            preferences.defaults.set([850.0, 620.0], forKey: "palettePosition")
            palette.layoutInContainer(initial: true)
            #expect(palette.frame.origin == NSPoint(x: 850, y: 620))
            container.setFrameSize(NSSize(width: 420, height: 320)); palette.layoutInContainer()
            #expect(container.bounds.contains(palette.frame))
            container.setFrameSize(NSSize(width: 1200, height: 800)); palette.layoutInContainer()
            #expect(palette.frame.origin == NSPoint(x: 850, y: 620))
            preferences.defaults.set([Double.nan, Double.infinity], forKey: "palettePosition")
            palette.layoutInContainer(initial: true)
            #expect(palette.frame.minX.isFinite && palette.frame.minY.isFinite)
        }
    }

    @Test func losingWindowFocusCancelsSortWithoutSavingAndDeletionKeepsSlotsContiguous() throws {
        try withPalette { palette, preferences in
            let (window, canvas) = CanvasTests().makeCanvas()
            canvas.addSubview(palette)
            let colors = palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" }
            let original = palette.colors
            let start = NSPoint(x: colors[0].frame.midX, y: colors[0].frame.midY)
            let end = NSPoint(x: colors[5].frame.midX, y: colors[5].frame.midY)
            palette.beginReordering(colors[0], at: start); palette.updateReordering(at: end)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            palette.endReordering(at: end)
            #expect(palette.colors == original)
            #expect(preferences.defaults.stringArray(forKey: "lightPresets") == nil)
            palette.beginReordering(colors[0], at: start); palette.updateReordering(at: end)
            palette.deletePreset(2)
            palette.endReordering(at: end)
            #expect(palette.colors == original.enumerated().filter { $0.offset != 2 }.map(\.element))
            let visible = colors.filter { !$0.isHidden }.sorted { $0.tag < $1.tag }
            #expect(visible.enumerated().allSatisfy { $0.element.frame.minX == CGFloat(20 + $0.offset * 34) })
        }
    }
}
