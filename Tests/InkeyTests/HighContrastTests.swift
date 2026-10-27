import AppKit
import Testing
@testable import Inkey

@Suite("High contrast display", .serialized)
@MainActor
struct HighContrastTests {
    @Test func automaticEntryReenablesEachTimeAndRestoresThePaperState() throws {
        try ScreenDraftTests().withApp { app in
            #expect(!app.preferences.autoHighContrastOnScreen)
            let settings = app.makeSettingsWindow()
            defer { settings.close() }
            let option = try #require(settings.contentView?.allSubviews.compactMap { $0 as? NSSwitch }.first {
                $0.action == #selector(InkeyApp.changeAutoHighContrast(_:))
            })
            option.state = .on; app.changeAutoHighContrast(option)
            #expect(UserPreferences(defaults: app.preferences.defaults).autoHighContrastOnScreen)
            app.enterScreenDraft()
            #expect(app.canvas.highContrastEnabled && app.palette.highContrastEnabled)
            app.toggleHighContrast(nil)
            #expect(!app.canvas.highContrastEnabled)
            app.exitScreenDraft(restoreWindow: false, activatePrevious: false)
            #expect(!app.canvas.highContrastEnabled && !app.preferences.highContrast)
            app.enterScreenDraft()
            #expect(app.canvas.highContrastEnabled)
            app.toggleHighContrast(nil)
            app.exitScreenDraft(restoreWindow: false, activatePrevious: false)
            option.state = .off; app.changeAutoHighContrast(option)
            app.enterScreenDraft()
            #expect(!app.canvas.highContrastEnabled)
        }
    }
    @Test func rapidTogglesFadeToTheLatestStateWithoutEndingEditing() throws {
        try ScreenDraftTests().withApp { app in
            app.window.orderFront(nil)
            app.canvas.beginText(at: NSPoint(x: 200, y: 200))
            let editor = try #require(app.window.firstResponder as? InlineTextView)
            editor.insertText("live", replacementRange: NSRange(location: 0, length: 0))
            app.canvas.setHighContrast(true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                #expect(app.canvas.contrastStrength > 0 && app.canvas.contrastStrength < 1)
            }
            app.canvas.setHighContrast(false)
            app.canvas.setHighContrast(true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            #expect(app.canvas.contrastStrength == 1 && app.canvas.highContrastEnabled)
            #expect(app.window.firstResponder === editor && app.canvas.isEditing && editor.string == "live")
            #expect(app.canvas.draft.items.isEmpty)
        }
    }
    func bitmap(_ canvas: CanvasView) throws -> NSBitmapImageRep {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        return bitmap
    }

    @Test func contoursKeepScreenThicknessAndNeverChangeTheDraft() throws {
        try ScreenDraftTests().withApp { app in
            let canvas = app.canvas
            canvas.cursorTrailEnabled = false
            canvas.draft.background = InkColor("808080")
            canvas.draft.items = [InkItem(kind: .line, points: [InkPoint(NSPoint(x: 100, y: 100)), InkPoint(NSPoint(x: 300, y: 100))], color: InkColor("E02020"), lineWidth: 3)]
            var addedThickness: [Int] = []
            for zoom in [0.5, 1.0, 2.0] {
                canvas.draft.zoom = zoom
                let original = canvas.draft
                canvas.setHighContrast(false, animated: false)
                let plain = try bitmap(canvas)
                canvas.setHighContrast(true, animated: false)
                let enhanced = try bitmap(canvas)
                #expect(canvas.draft == original)
                let x = Int(200 * zoom * Double(enhanced.pixelsWide) / canvas.bounds.width)
                func coloredRows(_ image: NSBitmapImageRep) -> Int {
                    (0..<image.pixelsHigh).filter { y in
                        guard let c = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return max(abs(c.redComponent - 0.5), abs(c.greenComponent - 0.5), abs(c.blueComponent - 0.5)) > 0.1
                    }.count
                }
                let thickness = coloredRows(enhanced) - coloredRows(plain)
                #expect(thickness > 0)
                addedThickness.append(thickness)
                canvas.setHighContrast(false, animated: false)
                let restored = try bitmap(canvas)
                #expect(restored.representation(using: .png, properties: [:]) == plain.representation(using: .png, properties: [:]))
            }
            #expect((addedThickness.max() ?? 0) - (addedThickness.min() ?? 0) <= 2)
        }
    }

    @Test func textExportsUseContoursAndImagesStayIdentical() throws {
        try ScreenDraftTests().withApp { app in
            let canvas = app.canvas
            canvas.draft.items = [InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor("FFFFFF"), text: "高对比 Aa", fontSize: 24)]
            let original = canvas.draft
            let plain = try #require(canvas.exportData(pdf: false))
            canvas.setHighContrast(true, animated: false)
            #expect(canvas.exportData(pdf: false) != plain)
            #expect((canvas.exportData(pdf: true)?.count ?? 0) > 100)
            #expect(canvas.draft == original)
            let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
                NSColor.systemPink.setFill(); rect.fill(); return true
            }
            canvas.draft.items = [InkItem(kind: .image, points: [InkPoint(NSPoint(x: 100, y: 100))], color: canvas.ink,
                                         imageData: image.tiffRepresentation, imageWidth: 40, imageHeight: 30)]
            let enhanced = canvas.exportData(pdf: false)
            canvas.setHighContrast(false, animated: false)
            #expect(enhanced == canvas.exportData(pdf: false))
        }
    }

    @Test func togglingDuringCompositionPreservesTheNativeEditorAndRawAttributes() throws {
        try ScreenDraftTests().withApp { app in
            app.canvas.beginText(at: NSPoint(x: 200, y: 200))
            let editor = try #require(app.window.firstResponder as? InlineTextView)
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let original = NSAttributedString(attributedString: try #require(editor.textStorage))
            let frame = editor.frame, selection = editor.selectedRange()
            app.palette.toggleHighContrast()
            app.canvas.setHighContrast(true, animated: false)
            _ = try bitmap(app.canvas)
            #expect(app.window.firstResponder === editor && editor.hasMarkedText())
            #expect(editor.selectedRange() == selection && editor.frame == frame)
            #expect(editor.textStorage?.isEqual(to: original) == true)
            #expect(app.preferences.highContrast && app.palette.highContrastEnabled)
            #expect(app.canvas.draft.items.isEmpty)
        }
    }

    @Test func shortcutCanToggleDuringDrawingWithoutChangingToolsOrUndo() throws {
        try ScreenDraftTests().withApp { app in
            let helper = CanvasTests()
            app.canvas.mouseDown(with: helper.mouse(.leftMouseDown, NSPoint(x: 150, y: 150), window: app.window))
            app.canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, NSPoint(x: 230, y: 180), window: app.window))
            #expect(app.canvas.isDrawing)
            let originalInk = app.canvas.ink
            let event = KeyboardShortcutTests().event(4, [.command, .option], window: app.window)
            #expect(app.handleConfiguredShortcut(event))
            #expect(app.canvas.highContrastEnabled && app.canvas.isDrawing && app.canvas.ink == originalInk)
            app.canvas.mouseUp(with: helper.mouse(.leftMouseUp, NSPoint(x: 230, y: 180), window: app.window))
            #expect(app.canvas.draft.items.count == 1)
            app.canvas.undo(nil)
            #expect(app.canvas.draft.items.isEmpty && app.canvas.highContrastEnabled)
        }
    }

    @Test func paperAndScreenRememberSeparateStatesAndMenuAndButtonAgree() throws {
        try ScreenDraftTests().withApp { app in
            let old = NSApp.mainMenu
            defer { NSApp.mainMenu = old }
            app.buildMenu()
            app.toggleHighContrast(nil)
            #expect(app.preferences.highContrast && app.palette.highContrastEnabled)
            app.enterScreenDraft()
            #expect(!app.canvas.highContrastEnabled && !app.palette.highContrastEnabled)
            app.toggleHighContrast(nil)
            #expect(app.preferences.screenHighContrast)
            app.exitScreenDraft(restoreWindow: false, activatePrevious: false)
            #expect(app.canvas.highContrastEnabled && app.palette.highContrastEnabled)
            let view = try #require(NSApp.mainMenu?.items.first { $0.title == "视图" }?.submenu)
            let menu = try #require(view.items.first { $0.action == #selector(InkeyApp.toggleHighContrast(_:)) })
            #expect(menu.state == .on && menu.keyEquivalent == "h")
            let restored = InkeyApp(preferences: app.preferences, store: app.store)
            restored.buildWindow(); restored.canvas.onChange = nil
            defer { restored.window.orderOut(nil) }
            #expect(restored.canvas.highContrastEnabled && restored.palette.highContrastEnabled)
            app.preferences.shortcuts.set(KeyBinding(40, [.command, .option], "k"), for: .highContrast)
            app.refreshShortcutUI()
            #expect(menu.keyEquivalent == "k")
        }
    }
}
