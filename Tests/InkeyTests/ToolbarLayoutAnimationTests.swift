import AppKit
import QuartzCore
import Testing
@testable import Inkey

@Suite("Toolbar compaction animation", .serialized)
@MainActor
struct ToolbarLayoutAnimationTests {
    @Test func addingAColorAnimatesTheNewSwatchAndExpandsTheShell() throws {
        try fixture { palette, window in
            _ = palette.makeColorPopover(purpose: .add)
            let picker = try #require(palette.popover?.contentViewController as? ColorPanelController)
            _ = picker.view
            picker.update(InkColor("123456"), syncSquare: true)
            picker.addPreset()
            window.displayIfNeeded()
            let new = try #require(swatches(palette).last)
            #expect(new.inkColor == InkColor("123456") && palette.bounds.height == 118)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(new.layer?.animation(forKey: "toolbarReflow.opacity") != nil)
                #expect(palette.layer?.animation(forKey: "toolbarReflow.bounds") != nil)
            }
        }
    }
    func fixture(_ body: (PaletteView, NSWindow) throws -> Void) throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView?.wantsLayer = true
            window.contentView?.addSubview(palette)
            palette.layoutInContainer(initial: true)
            window.orderFront(nil); window.displayIfNeeded()
            defer { palette.setToolbarHidden(true); window.orderOut(nil) }
            try body(palette, window)
        }
    }

    func swatches(_ palette: PaletteView) -> [SwatchButton] {
        palette.subviews.compactMap { $0 as? SwatchButton }.filter { $0.reorderGroup == "colors" && !$0.isHidden }.sorted { $0.tag < $1.tag }
    }

    @Test func survivingColorsSlideWhileTheShellShrinksAndNativeHitsStayCurrent() throws {
        try fixture { palette, window in
            let original = swatches(palette)
            let color = original[2].inkColor
            let position = try #require(original[2].layer).position
            palette.deletePreset(1)
            window.displayIfNeeded()
            let remaining = swatches(palette)
            #expect(remaining[1] === original[2] && remaining[1].inkColor == color)
            #expect(original[1].isHidden)
            #expect(palette.bounds.width == 286)
            let center = remaining[1].convert(NSPoint(x: 17, y: 18), to: palette.superview)
            #expect(palette.hitTest(center) === remaining[1])
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(remaining[1].layer?.animation(forKey: "toolbarReflow.position") == nil)
            } else {
                let slide = try #require(remaining[1].layer?.animation(forKey: "toolbarReflow.position") as? CABasicAnimation)
                #expect((slide.fromValue as? NSValue)?.pointValue == position)
                #expect(slide.duration == ToolbarLayoutAnimation.duration)
                #expect(palette.layer?.animation(forKey: "toolbarReflow.bounds") != nil)
            }
        }
    }

    @Test func rapidDeletionContinuesFromTheCurrentPresentation() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try fixture { palette, window in
            let survivor = swatches(palette)[4]
            palette.deletePreset(0)
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
            let shown = try #require(survivor.layer?.presentation()).position
            palette.deletePreset(0)
            let animation = try #require(survivor.layer?.animation(forKey: "toolbarReflow.position") as? CABasicAnimation)
            let from = try #require((animation.fromValue as? NSValue)?.pointValue)
            #expect(hypot(from.x - shown.x, from.y - shown.y) < 3)
            #expect(palette.colors.count == 4)
            window.displayIfNeeded()
        }
    }

    @Test func removingAnEmptyRowAnimatesTheShapeControlsAndCancelsOnInteraction() throws {
        try fixture { palette, window in
            palette.addPreset(InkColor("123456"))
            RunLoop.current.run(until: Date().addingTimeInterval(ToolbarLayoutAnimation.duration + 0.03))
            window.displayIfNeeded()
            let shape = try #require(palette.subviews.compactMap { $0 as? ToolButton }.first { $0.reorderGroup == "shapes" })
            palette.deletePreset(6)
            #expect(palette.bounds.height == 80)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(shape.layer?.animation(forKey: "toolbarReflow.position") != nil)
            }
            palette.toggleCollapsed()
            #expect(shape.layer?.animation(forKey: "toolbarReflow.position") == nil)
            palette.toggleCollapsed()
            palette.deletePreset(0)
            palette.setToolbarScale(1.25)
            #expect(palette.subviews.allSatisfy { view in
                !(view.layer?.animationKeys() ?? []).contains { $0.hasPrefix("toolbarReflow.") }
            })
            #expect(palette.layer?.animation(forKey: "toolbarReflow.bounds") == nil)
        }
    }
}
