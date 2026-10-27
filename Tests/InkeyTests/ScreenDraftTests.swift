import AppKit
import Testing
@testable import Inkey

@Suite("Transparent screen drafts", .serialized)
@MainActor
struct ScreenDraftTests {
    func withApp(_ body: (InkeyApp) throws -> Void) throws {
        _ = NSApplication.shared
        let suite = "InkeyScreenDraftTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let app = InkeyApp(preferences: UserPreferences(defaults: defaults), store: DraftStore(directory: directory))
        app.buildWindow()
        defer {
            app.canvas.onChange = nil; app.screenCanvas?.onChange = nil
            app.canvasPresentation?.canvas.onChange = nil
            app.exitScreenDraft(restoreWindow: false, activatePrevious: false)
            app.window.orderOut(nil); app.screenWindow?.orderOut(nil); app.settings?.orderOut(nil)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(app)
    }

    @Test func overlayCoversTargetScreenAndRestoresOriginalCanvasAndUndo() throws {
        try withApp { app in
            let screen = try #require(NSScreen.main)
            let originalWindow = app.window!, originalCanvas = app.canvas
            let originalFrame = originalWindow.frame
            let file = URL(fileURLWithPath: "/tmp/original.inkey")
            app.fileURL = file
            let item = InkItem(kind: .text, points: [InkPoint(NSPoint(x: 120, y: 120))], color: app.canvas.ink, text: "original")
            originalCanvas.replaceItems([item], name: "Original")
            app.enterScreenDraft(on: screen)
            #expect(app.isScreenDraft && app.window !== originalWindow && app.canvas !== originalCanvas)
            #expect(app.window.frame == screen.frame)
            #expect(app.window.styleMask == .borderless && !app.window.isOpaque && !app.window.hasShadow)
            #expect(app.window.level == .statusBar && !app.window.ignoresMouseEvents)
            #expect(app.canvas.transparentBackground && app.canvas.draft.items.isEmpty)
            #expect(app.palette.superview === app.window.contentView)
            #expect(app.window.contentView?.subviews.compactMap { $0 as? NSButton }.count == 2)
            app.exitScreenDraft(restoreWindow: false, activatePrevious: false)
            #expect(!app.isScreenDraft && app.window === originalWindow && app.canvas === originalCanvas)
            #expect(app.fileURL == file && app.window.frame == originalFrame)
            #expect(app.palette.superview === originalWindow.contentView)
            originalCanvas.undo(nil)
            #expect(originalCanvas.draft.items.isEmpty)
        }
    }

    @Test func screenTypingAndAutosaveDoNotReplaceNormalDraftAndSurviveReentry() throws {
        try withApp { app in
            let original = app.canvas.draft.id
            app.enterScreenDraft()
            let overlay = app.canvas
            let identifier = overlay.draft.id
            overlay.beginText(at: NSPoint(x: 300, y: 220))
            let editor = try #require(overlay.subviews.compactMap { $0 as? InlineTextView }.first)
            editor.insertText("screen note", replacementRange: NSRange(location: 0, length: 0))
            let escape = KeyboardShortcutTests().event(53, [], window: app.window)
            #expect(app.handleScreenDraftEscape(escape))
            #expect(!app.isScreenDraft && app.canvas.draft.id == original)
            #expect(app.preferences.defaults.string(forKey: "currentDraft") == original.uuidString)
            #expect(app.preferences.defaults.string(forKey: "screenDraft") == identifier.uuidString)
            let saved = try #require(app.store.recent().first { $0.1.id == identifier }?.1)
            #expect(saved.items.first?.text == "screen note")
            app.enterScreenDraft()
            #expect(app.canvas === overlay && app.canvas.draft.id == identifier)
            #expect(app.canvas.draft.items.first?.text == "screen note")
            app.canvas.undo(nil)
            #expect(app.canvas.draft.items.isEmpty)
        }
    }

    @Test func restoresSavedScreenDraftAndKeepsToolsAndDrawingRouting() throws {
        try withApp { app in
            var saved = Draft()
            saved.items = [InkItem(kind: .text, points: [InkPoint(NSPoint(x: 100, y: 100))], color: InkColor.light[0], text: "saved screen")]
            try app.store.save(saved)
            app.preferences.defaults.set(saved.id.uuidString, forKey: "screenDraft")
            app.preferences.shiftShape = .rectangle
            app.enterScreenDraft()
            #expect(app.canvas.draft == saved && app.canvas.shiftShape == .rectangle)
            let helper = CanvasTests()
            app.canvas.mouseDown(with: helper.mouse(.leftMouseDown, NSPoint(x: 300, y: 350), window: app.window))
            app.canvas.mouseDragged(with: helper.mouse(.leftMouseDragged, NSPoint(x: 400, y: 370), window: app.window))
            app.canvas.mouseUp(with: helper.mouse(.leftMouseUp, NSPoint(x: 400, y: 370), window: app.window))
            #expect(app.canvas.draft.items.last?.kind == .stroke)
            #expect(app.canvas.draft.items.count == 2)
            app.canvas.undo(nil)
            #expect(app.canvas.draft.items == saved.items)
            app.palette.chooseShape(.ellipse)
            app.palette.toggleEraser()
            app.exitScreenDraft(restoreWindow: false, activatePrevious: false)
            #expect(app.canvas.shiftShape == .ellipse && app.canvas.eraserEnabled)
        }
    }

    @Test func transparentInputSurfaceStaysHitTestableAfterDrawingAndErasing() throws {
        try withApp { app in
            app.enterScreenDraft()
            let canvas = app.canvas
            let rect = NSRect(x: 0, y: 0, width: 100, height: 100)
            let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: rect))
            canvas.cacheDisplay(in: rect, to: bitmap)
            let inputAlpha = try #require(bitmap.colorAt(x: 20, y: 20)).alphaComponent
            #expect(inputAlpha >= 0.005 && inputAlpha <= 0.015)
            canvas.replaceItems([InkItem(kind: .stroke, points: [InkPoint(NSPoint(x: 10, y: 10)), InkPoint(NSPoint(x: 90, y: 90))], color: InkColor("FF0000"), lineWidth: 6)], name: "Draw")
            canvas.cacheDisplay(in: rect, to: bitmap)
            #expect(try #require(bitmap.colorAt(x: 50, y: 50)).alphaComponent > 0)
            canvas.undo(nil)
            canvas.cacheDisplay(in: rect, to: bitmap)
            #expect(try #require(bitmap.colorAt(x: 50, y: 50)).alphaComponent == inputAlpha)
        }
    }

    @Test func globalShortcutsStayDistinctAndNormalShortcutReturnsToPaper() throws {
        try withApp { app in
            #expect(ShortcutAction.screenDraft.isGlobal)
            #expect(app.hotkey.identifier != app.screenHotkey.identifier)
            #expect(app.shortcuts.label(for: .screenDraft) == "⌃⌥S")
            #expect(app.shortcuts.validationMessage(ShortcutAction.toggleWindow.defaultBinding, for: .screenDraft) != nil)
            #expect(!app.handleConfiguredShortcut(KeyboardShortcutTests().event(1, [.control, .option])))
            app.handleGlobalShortcut(.screenDraft)
            #expect(app.isScreenDraft)
            app.handleGlobalShortcut(.toggleWindow)
            #expect(!app.isScreenDraft && app.window.isVisible)
            app.handleGlobalShortcut(.screenDraft)
            #expect(app.isScreenDraft)
            app.handleGlobalShortcut(.screenDraft)
            #expect(!app.isScreenDraft && app.window.isVisible)
            #expect(app.screenWindow?.isVisible == false)
        }
    }
}
