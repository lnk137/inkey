import AppKit
import Testing
@testable import Inkey

@Suite("Toolbar collapse compositor", .serialized)
@MainActor
struct ToolbarCollapseAnimationTests {
    func fixture(_ body: (PaletteView, CollapseButton, ToolbarCollapseAnimation) throws -> Void) throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let (window, canvas) = CanvasTests().makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            window.displayIfNeeded(); canvas.displayIfNeeded()
            let button = try #require(palette.subviews.compactMap { $0 as? CollapseButton }.first)
            try body(palette, button, ToolbarCollapseAnimation())
            window.orderOut(nil)
        }
    }

    @Test func collapseUsesOneSmallTextureAndLeavesNativeHitTestingIntact() throws {
        try fixture { palette, button, animation in
            let layer = try #require(palette.layer)
            let before = try #require(animation.capture(in: palette, button: button, collapsed: false))
            let parent = try #require(layer.superlayer)
            let initialLayerCount = parent.sublayers?.count
            let image = try #require(before.image)
            #expect(image.width < 2000 && image.height < 1000)
            palette.toggleCollapsed()
            animation.animate(from: before, in: palette, button: button, collapsed: true)
            #expect(animation.isAnimating)
            #expect(layer.opacity == 1 && palette.alphaValue == 1)
            #expect(layer.animation(forKey: "toolbarCollapseVisibility")?.duration == ToolbarCollapseAnimation.duration)
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: palette.superview)
            #expect(palette.hitTest(center) === button)
            #expect(parent.sublayers?.filter { $0.name == "Inkey.toolbarCollapse" }.count == 1)
            let container = try #require(palette.superview)
            let oldCenter = NSPoint(x: before.arrowFrame.midX, y: before.arrowFrame.midY)
            #expect(container.subviews.last?.hitTest(oldCenter) === button)
            #expect(palette.frame.width == 36)
            animation.finish()
            #expect(!animation.isAnimating)
            #expect(parent.sublayers?.count == initialLayerCount)
            #expect(layer.animation(forKey: "toolbarCollapseVisibility") == nil)
        }
    }

    @Test func rapidReversalsReuseTheTextureAndKeepOnlyOneOverlay() throws {
        try fixture { palette, button, animation in
            let parent = try #require(palette.layer?.superlayer)
            let count = parent.sublayers!.count
            let initial = try #require(animation.capture(in: palette, button: button, collapsed: false))
            let image = try #require(initial.image)
            var state = initial
            for _ in 0..<12 {
                palette.toggleCollapsed()
                animation.animate(from: state, in: palette, button: button, collapsed: palette.isCollapsed)
                state = try #require(animation.capture(in: palette, button: button, collapsed: palette.isCollapsed))
                #expect(state.image === image)
                #expect(parent.sublayers?.filter { $0.name == "Inkey.toolbarCollapse" }.count == 1)
                #expect(button.frame.size == NSSize(width: 36, height: 36))
            }
            animation.finish()
            #expect(parent.sublayers!.count == count)
            #expect(palette.layer?.animationKeys()?.isEmpty ?? true)
        }
    }

    @Test func firstExpansionCapturesContentAfterLayout() throws {
        try fixture { palette, button, animation in
            palette.toggleCollapsed()
            let before = try #require(animation.capture(in: palette, button: button, collapsed: true))
            #expect(before.image == nil)
            palette.toggleCollapsed()
            animation.animate(from: before, in: palette, button: button, collapsed: false)
            #expect(animation.isAnimating)
            let state = try #require(animation.capture(in: palette, button: button, collapsed: false))
            #expect(state.image != nil && state.contentBounds.width > 36)
            animation.finish()
            #expect(palette.subviews.filter { !$0.isHidden }.count > 1)
        }
    }

    @Test func completionReleasesTheOverlayAndRestoresLiveDrawing() async throws {
        let name = "InkeyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let (window, canvas) = CanvasTests().makeCanvas()
        let palette = PaletteView(frame: .zero, preferences: UserPreferences(defaults: defaults))
        canvas.addSubview(palette); palette.layoutInContainer(initial: true)
        window.displayIfNeeded(); canvas.displayIfNeeded()
        let button = try #require(palette.subviews.compactMap { $0 as? CollapseButton }.first)
        let animation = ToolbarCollapseAnimation()
        let before = try #require(animation.capture(in: palette, button: button, collapsed: false))
        palette.toggleCollapsed()
        animation.animate(from: before, in: palette, button: button, collapsed: true)
        #expect(animation.isAnimating)
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(!animation.isAnimating)
        #expect(palette.layer?.animation(forKey: "toolbarCollapseVisibility") == nil)
        #expect(palette.alphaValue == 1)
        window.orderOut(nil)
    }

    @Test func visibleToggleRoutesClicksOnTheMovingChevronAndHideCleansUp() throws {
        try PaletteReorderingTests().withPalette { palette, _ in
            let (window, canvas) = CanvasTests().makeCanvas()
            canvas.addSubview(palette); palette.layoutInContainer(initial: true)
            window.orderFront(nil); window.displayIfNeeded()
            defer { window.orderOut(nil) }
            let button = try #require(palette.subviews.compactMap { $0 as? CollapseButton }.first)
            let oldCenter = button.convert(NSPoint(x: 18, y: 18), to: nil)
            palette.toggleCollapsed()
            #expect(palette.isCollapsed)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(palette.layer?.animation(forKey: "toolbarCollapseVisibility") != nil)
                let helper = CanvasTests()
                button.mouseDown(with: helper.mouse(.leftMouseDown, oldCenter, window: window))
                button.mouseUp(with: helper.mouse(.leftMouseUp, oldCenter, window: window))
                #expect(!palette.isCollapsed)
            }
            palette.setToolbarHidden(true)
            #expect(palette.layer?.animation(forKey: "toolbarCollapseVisibility") == nil)
            #expect(canvas.subviews.filter { $0 !== palette && !($0 is InlineTextView) }.isEmpty)
        }
    }
}
