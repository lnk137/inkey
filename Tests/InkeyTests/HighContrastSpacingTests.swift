import AppKit
import Testing
@testable import Inkey

@Suite("Adjustable high contrast text spacing", .serialized)
@MainActor
struct HighContrastSpacingTests {
    @Test func settingsAdjustSpacingLiveWithoutEndingCompositionOrAddingUndo() throws {
        try ScreenDraftTests().withApp { app in
            #expect(app.preferences.highContrastTextSpacing == 4)
            let settings = app.makeSettingsWindow()
            defer { settings.close() }
            let slider = try #require(settings.contentView?.allSubviews.compactMap { $0 as? NSSlider }.first {
                $0.action == #selector(InkeyApp.changeHighContrastSpacing(_:))
            })
            app.canvas.setHighContrast(true, animated: false)
            app.canvas.beginText(at: NSPoint(x: 300, y: 200))
            let editor = try #require(app.window.firstResponder as? InlineTextView)
            editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let width = editor.frame.width, center = editor.frame.midX
            let undo = editor.undoManager?.canUndo
            slider.doubleValue = 9.3; app.changeHighContrastSpacing(slider)
            #expect(app.preferences.highContrastTextSpacing == 9.5)
            #expect(UserPreferences(defaults: app.preferences.defaults).highContrastTextSpacing == 9.5)
            #expect(app.contrastSpacingLabel?.stringValue == "9.5 pt")
            #expect(editor.hasMarkedText() && editor.selectedRange() == NSRange(location: 5, length: 0))
            #expect(app.window.firstResponder === editor && editor.frame.width > width && editor.frame.midX == center)
            #expect(editor.undoManager?.canUndo == undo && app.canvas.draft.items.isEmpty)
        }
    }

    @Test func existingTextKeepsItsCenterAndMatchesNativeEditingAndCommit() throws {
        try ScreenDraftTests().withApp { app in
            let canvas = app.canvas
            let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 150, y: 100))], color: InkColor("57C95B"), text: "的我我 的W的", fontSize: 24)
            canvas.draft.items = [item]
            canvas.setHighContrast(true, animated: false)
            for zoom in [0.5, 1.0, 2.0] {
                canvas.draft.zoom = zoom
                let bounds = canvas.displayBounds(for: item)
                #expect(bounds.width > item.bounds.width && bounds.midX == item.bounds.midX)
                #expect(canvas.displayTextTracking * zoom == 4)
                #expect(canvas.item(at: NSPoint(x: bounds.minX + 1, y: bounds.midY))?.id == item.id)
                canvas.beginText(at: item.points[0].point, item: item, showCaret: false)
                let editor = try #require(canvas.subviews.compactMap { $0 as? InlineTextView }.first)
                #expect(abs(editor.frame.width - bounds.width * zoom) < 0.001)
                #expect(abs(editor.frame.minX - canvas.screen(bounds.origin).x) < 0.001)
                canvas.commitText()
                #expect(canvas.draft.items == [item])
            }
            canvas.setHighContrast(false, animated: false)
            #expect(canvas.displayBounds(for: item) == item.bounds)
        }
    }

    @Test func exportIncludesWideTrackingWithoutChangingOriginalContent() throws {
        try ScreenDraftTests().withApp { app in
            let canvas = app.canvas
            let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 150, y: 100))], color: InkColor("57C95B"), text: "的我我 的W的 repeated", fontSize: 24)
            canvas.draft.items = [item]
            canvas.setHighContrast(true, animated: false)
            app.preferences.highContrastTextSpacing = 0
            let compact = try #require(canvas.exportData(pdf: false))
            app.preferences.highContrastTextSpacing = 12
            let wide = try #require(canvas.exportData(pdf: false))
            let a = try #require(NSBitmapImageRep(data: compact)), b = try #require(NSBitmapImageRep(data: wide))
            #expect(b.pixelsWide > a.pixelsWide + 100)
            #expect(canvas.draft.items == [item])
            canvas.setHighContrast(false, animated: false)
            #expect(canvas.displayTextTracking == 0 && canvas.displayBounds(for: item) == item.bounds)
        }
    }

    @Test func resizingSpacedTextKeepsTheOppositeDisplayCornerFixed() {
        let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 150, y: 100))], color: InkColor("57C95B"), text: "的我我 的W的", fontSize: 24)
        let bounds = InkTypography.displayBounds(for: item, tracking: 6)
        for corner in TextResizeCorner.allCases {
            let start = corner.point(in: bounds)
            let gesture = TextResizeGesture(items: [item], item: item, corner: corner, start: start, textTracking: 6)
            let opposite = TextResizeCorner.allCases.first { $0.isLeft != corner.isLeft && $0.isTop != corner.isTop }!
            let resized = gesture.resized(to: NSPoint(x: start.x + (corner.isLeft ? -40 : 40), y: start.y + (corner.isTop ? -20 : 20)))
            let after = opposite.point(in: InkTypography.displayBounds(for: resized, tracking: 6))
            let fixed = opposite.point(in: bounds)
            #expect(abs(after.x - fixed.x) < 0.001 && abs(after.y - fixed.y) < 0.001)
        }
    }

    @Test func invalidSpacingValuesAreClampedAndNormalTextIsUnaffected() throws {
        try ScreenDraftTests().withApp { app in
            for (value, expected) in [(Double.nan, 4.0), (.infinity, 4), (-3, 0), (100, 12)] {
                app.preferences.highContrastTextSpacing = value
                #expect(app.preferences.highContrastTextSpacing == expected)
            }
            #expect(app.canvas.displayTextTracking == 0)
            app.canvas.setHighContrast(true, animated: false)
            #expect(app.canvas.displayTextTracking == 12)
        }
    }
}
