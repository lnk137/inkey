import AppKit
import Testing
@testable import Inkey

@Suite("Toolbar layout and resizing", .serialized)
@MainActor
struct ToolbarLayoutTests {
    let helper = CanvasTests()

    @Test func compactChevronDragsTheToolbarAndClickExpandsWithoutSavingPosition() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            let (window, canvas) = helper.makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            palette.toggleCollapsed(); palette.layoutInContainer()
            let start = palette.convert(NSPoint(x: 18, y: 18), to: nil)
            let hit = palette.hitTest(canvas.convert(start, from: nil))
            let chevron = try #require(hit as? ToolButton)
            chevron.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            chevron.mouseUp(with: helper.mouse(.leftMouseUp, start, window: window))
            #expect(!palette.isCollapsed)
            #expect(preferences.defaults.object(forKey: "palettePosition") == nil)
            palette.toggleCollapsed(); palette.layoutInContainer()
            let original = palette.frame.origin
            let parentPoint = canvas.convert(start, from: nil)
            let end = canvas.convert(NSPoint(x: parentPoint.x + 70, y: parentPoint.y + 30), to: nil)
            chevron.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            chevron.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            chevron.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(palette.isCollapsed)
            #expect(palette.frame.minX == original.x + 70)
            let deltaInParent = canvas.convert(end, from: nil).y - canvas.convert(start, from: nil).y
            #expect(palette.frame.minY == original.y + deltaInParent)
            #expect(preferences.defaults.array(forKey: "palettePosition") != nil)
            #expect(!palette.subviews.contains { ($0.toolTip ?? "").contains("隐藏工具栏") })
        }
    }

    @Test func scalingPreservesLogicalLayoutHitTargetsAndRestartPreference() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            let (_, canvas) = helper.makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            for scale in [0.85, 1, 1.25, 1.5] {
                palette.setToolbarScale(scale)
                #expect(palette.frame.size == NSSize(width: 320 * scale, height: 80 * scale))
                #expect(palette.bounds.size == NSSize(width: 320, height: 80))
                for button in palette.subviews.compactMap({ $0 as? ReorderButton }).filter({ !$0.isHidden }) {
                    let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: canvas)
                    #expect(palette.hitTest(center) === button)
                }
                palette.toggleCollapsed(); palette.layoutInContainer()
                #expect(palette.frame.size == NSSize(width: 36 * scale, height: 36 * scale))
                palette.toggleCollapsed(); palette.layoutInContainer()
            }
            let restored = PaletteView(frame: palette.frame, preferences: preferences)
            #expect(restored.toolbarScale == 1.5 && restored.frame.width == 480)
        }
    }

    @Test func resizingSavesOnceAndEscapeRestoresTheOriginalScale() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            let (_, canvas) = helper.makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            let start = palette.convert(NSPoint(x: 308, y: 68), to: nil)
            palette.beginResizing(at: start)
            palette.updateResizing(at: NSPoint(x: start.x + 80, y: start.y))
            #expect(palette.toolbarScale == 1.25)
            #expect(preferences.defaults.object(forKey: "toolbarScale") == nil)
            #expect(palette.cancelActiveGesture())
            #expect(palette.toolbarScale == 1 && palette.frame.width == 320)
            palette.endResizing()
            #expect(preferences.defaults.object(forKey: "toolbarScale") == nil)
            palette.beginResizing(at: start)
            palette.updateResizing(at: NSPoint(x: start.x + 48, y: start.y))
            palette.endResizing()
            #expect(abs(preferences.toolbarScale - 1.15) < 0.0001)
            let original = palette.toolbarScale
            palette.beginResizing(at: start)
            palette.updateResizing(at: NSPoint(x: start.x - 200, y: start.y))
            palette.setToolbarHidden(true)
            #expect(palette.toolbarScale == original)
        }
    }

    @Test func resizeHandleRoutesMouseDragAndDoubleClickRestoresDefault() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            let (window, canvas) = helper.makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            let handle = try #require(palette.subviews.compactMap { $0 as? ToolbarResizeHandle }.first)
            let start = handle.convert(NSPoint(x: 10, y: 10), to: nil)
            let end = NSPoint(x: start.x + 32, y: start.y)
            handle.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            handle.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            handle.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(abs(preferences.toolbarScale - 1.1) < 0.0001)
            let doubleClick = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: end, modifierFlags: [], timestamp: 0,
                                                            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
            handle.mouseDown(with: doubleClick)
            #expect(preferences.toolbarScale == 1 && palette.frame.width == 320)
        }
    }

    @Test func narrowWindowsFitTheToolbarWithoutLosingTheRequestedSize() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            container.addSubview(palette); palette.layoutInContainer(initial: true)
            palette.setToolbarScale(1.5); palette.layoutInContainer()
            let original = palette.frame.origin
            for size in [NSSize(width: 420, height: 320), NSSize(width: 160, height: 90), NSSize(width: 40, height: 30)] {
                container.setFrameSize(size); palette.layoutInContainer()
                #expect(container.bounds.contains(palette.frame))
                #expect(palette.toolbarScale == 1.5)
            }
            container.setFrameSize(NSSize(width: 900, height: 600)); palette.layoutInContainer()
            #expect(palette.frame.width == 480 && palette.frame.origin == original)
        }
    }

    @Test func scaledReorderingUsesScreenMovementAndPreservesColorSlots() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let (window, canvas) = helper.makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            palette.setToolbarScale(1.5)
            let colors = palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" }
            let source = colors[0], original = palette.colors
            let start = source.convert(NSPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil)
            let end = colors[4].convert(NSPoint(x: colors[4].bounds.midX, y: colors[4].bounds.midY), to: nil)
            source.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
            source.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
            source.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
            #expect(palette.colors[4] == original[0])
            #expect(source.tag == 4 && source.frame.minX == 156)
        }
    }

    @Test func invalidSavedSizesClampAndFallBack() throws {
        try PaletteReorderingTests().withPalette { _, preferences in
            for (value, expected) in [(Double.nan, 1.0), (.infinity, 1), (-12, 0.85), (99, 1.5)] {
                preferences.defaults.set(value, forKey: "toolbarScale")
                #expect(preferences.toolbarScale == expected)
            }
        }
    }

    @Test func chevronHasTheSameScreenSizeAndNoBlueHighlightInBothStates() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
            container.addSubview(palette); palette.layoutInContainer(initial: true)
            palette.setToolbarScale(1.5); palette.layoutInContainer()
            let chevron = try #require(palette.subviews.compactMap { $0 as? CollapseButton }.first)
            let screenSize = chevron.convert(chevron.bounds, to: container).size
            for _ in 0..<4 {
                chevron.highlight(true)
                #expect(chevron.cell?.isHighlighted == false)
                #expect(chevron.frame.size == NSSize(width: 36, height: 36))
                let actual = chevron.convert(chevron.bounds, to: container).size
                #expect(abs(actual.width - screenSize.width) < 0.000001)
                #expect(abs(actual.height - screenSize.height) < 0.000001)
                palette.toggleCollapsed(); palette.layoutInContainer()
            }
        }
    }

    @Test func cancellingChevronDragRestoresPositionWithoutToggling() throws {
        try PaletteReorderingTests().withPalette { palette, preferences in
            let (window, canvas) = helper.makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            palette.setToolbarScale(1.25)
            let chevron = try #require(palette.subviews.compactMap { $0 as? ToolButton }.first { $0.onToolbarMouseEvent != nil })
            for collapsed in [false, true] {
                if palette.isCollapsed != collapsed { palette.toggleCollapsed(); palette.layoutInContainer() }
                let original = palette.frame.origin
                let start = chevron.convert(NSPoint(x: 15, y: 16), to: nil)
                let end = NSPoint(x: start.x + 40, y: start.y - 30)
                chevron.mouseDown(with: helper.mouse(.leftMouseDown, start, window: window))
                chevron.mouseDragged(with: helper.mouse(.leftMouseDragged, end, window: window))
                #expect(palette.cancelActiveGesture())
                chevron.mouseUp(with: helper.mouse(.leftMouseUp, end, window: window))
                #expect(palette.frame.origin == original)
                #expect(palette.isCollapsed == collapsed)
                #expect(preferences.defaults.object(forKey: "palettePosition") == nil)
            }
        }
    }

    @Test func hideIsOnlyInMoreAndSizeMenuWorksWithCollapsedAndHiddenToolbars() throws {
        try PaletteReorderingTests().withPalette { _, preferences in
            let app = InkeyApp(preferences: preferences)
            let originalMenu = NSApp.mainMenu
            defer { NSApp.mainMenu = originalMenu }
            app.buildMenu()
            let viewMenu = try #require(NSApp.mainMenu?.items.first { $0.title == "视图" }?.submenu)
            #expect(!viewMenu.items.contains { $0.action == #selector(InkeyApp.toggleToolbarHidden(_:)) })
            #expect(app.moreMenu().items.contains { $0.title == "隐藏工具栏" })
            app.palette.toggleCollapsed(); app.palette.setToolbarHidden(true)
            #expect(app.moreMenu().items.contains { $0.title == "显示工具栏" })
            let sizeMenu = app.toolbarSizeMenu()
            let large = try #require(sizeMenu.items.first { $0.tag == 125 })
            app.changeToolbarSize(large)
            #expect(app.palette.toolbarScale == 1.25)
            #expect(app.palette.isCollapsed && app.palette.isHidden)
            #expect(preferences.toolbarScale == 1.25)
            #expect(app.toolbarSizeMenu().items.first { $0.tag == 125 }?.state == .on)
            let (window, _) = helper.makeCanvas()
            let shortcut = helper.key("T", window: window, keyCode: 17, modifiers: [.command, .shift])
            #expect(app.handleToolbarVisibilityShortcut(shortcut))
            #expect(!app.palette.isHidden && app.palette.isCollapsed)
            #expect(!app.handleToolbarVisibilityShortcut(helper.key("t", window: window, keyCode: 17, modifiers: .command)))
        }
    }
}
