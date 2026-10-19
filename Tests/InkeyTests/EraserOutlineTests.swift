import AppKit
import Testing
@testable import Inkey

@Suite("Eraser outline", .serialized)
@MainActor
struct EraserOutlineTests {
    let helper = CanvasTests()
    @Test func temporaryAndPersistentOutlineFollowPointerAndScreenDiameter() throws {
        try TemporaryEraserTests().fixture { window, canvas, preferences in
            preferences.temporaryEraserModifier = .command
            let point = NSPoint(x: 320,y: 220)
            let location = canvas.convert(point, to: nil)
            canvas.mouseMoved(with: helper.mouse(.mouseMoved, location, window: window))
            #expect(canvas.eraserOutline.isHidden)
            canvas.flagsChanged(with: TemporaryEraserTests().flags(.command, window: window))
            for zoom in [0.2, 1, 4.0] {
                canvas.draft.zoom = zoom
                for diameter in [4.0, 24, 120] {
                    canvas.eraserDiameter = diameter
                    let rect = try #require(canvas.eraserOutlineRect)
                    #expect(rect.width == diameter && rect.midX == point.x && rect.midY == point.y)
                    #expect(canvas.eraserOutline.frame == rect.insetBy(dx: -2,dy: -2))
                    #expect(!canvas.eraserOutline.isHidden)
                    #expect(canvas.eraserOutline.hitTest(.zero) == nil)
                }
            }
            canvas.flagsChanged(with: TemporaryEraserTests().flags([], window: window))
            #expect(canvas.eraserOutline.isHidden)
            canvas.setEraserEnabled(true)
            #expect(!canvas.eraserOutline.isHidden)
            canvas.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
            #expect(canvas.eraserOutline.isHidden)
            canvas.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
            #expect(!canvas.eraserOutline.isHidden)
            canvas.isCanvasLocation = { _ in false }
            canvas.mouseMoved(with: helper.mouse(.mouseMoved, location, window: window))
            #expect(canvas.eraserOutline.isHidden)
        }
    }
    @Test func overlayIsVisibleAboveTextAndDoesNotAppearInExports() throws {
        try TemporaryEraserTests().fixture { window, canvas, _ in
            canvas.draft.items = [TemporaryEraserTests().line()]
            let before = try #require(canvas.exportData(pdf: false))
            canvas.setEraserEnabled(true)
            let location = canvas.convert(NSPoint(x: 320,y: 220), to: nil)
            canvas.mouseMoved(with: helper.mouse(.mouseMoved, location, window: window))
            #expect(canvas.subviews.last === canvas.eraserOutline)
            let overlay = canvas.eraserOutline
            let bitmap = try #require(overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds))
            overlay.cacheDisplay(in: overlay.bounds, to: bitmap)
            var opaquePixels = 0
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    if (bitmap.colorAt(x: x,y: y)?.alphaComponent ?? 0) > 0.1 { opaquePixels += 1 }
                }
            }
            #expect(opaquePixels > 30)
            #expect(opaquePixels < bitmap.pixelsWide * bitmap.pixelsHigh / 2)
            let after = try #require(canvas.exportData(pdf: false))
            #expect(before == after)
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            #expect(overlay.isHidden)
        }
    }
}
