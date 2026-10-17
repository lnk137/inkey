import AppKit
import Testing
@testable import Inkey

@Suite("Window shortcut toggle", .serialized)
@MainActor
struct WindowToggleTests {
    func makeApp() -> InkeyApp {
        _ = NSApplication.shared
        let app = InkeyApp()
        app.buildWindow()
        app.canvas.onChange = nil // Exercise window behavior without writing application drafts.
        app.pinned = true
        return app
    }

    @Test func visibleNonKeyWindowHidesAndRepeatedToggleRestoresIt() {
        let app = makeApp()
        defer { app.window.orderOut(nil) }
        app.window.orderFront(nil)
        #expect(app.window.isVisible)
        #expect(!app.window.isKeyWindow)
        app.toggleWindow()
        #expect(!app.window.isVisible)
        app.toggleWindow()
        #expect(app.window.isVisible)
        app.toggleWindow()
        #expect(!app.window.isVisible)
    }

    @Test func toggleWhileSettingsHasFocusHidesBothAndCommitsText() {
        let app = makeApp()
        defer { app.settings?.orderOut(nil); app.window.orderOut(nil) }
        app.window.orderFront(nil)
        app.canvas.beginText(at: NSPoint(x: 100, y: 100))
        let text = app.canvas.subviews.compactMap { $0 as? InlineTextView }.first!
        text.insertText("left", replacementRange: NSRange(location: 0, length: 0))
        let identifier = app.canvas.draft.id
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: .titled, backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        app.settings = settings
        settings.makeKeyAndOrderFront(nil)
        app.toggleWindow()
        #expect(!app.window.isVisible)
        #expect(!settings.isVisible)
        #expect(app.canvas.draft.id == identifier)
        #expect(app.canvas.draft.items.first?.text == "left")
        #expect(!app.canvas.isEditing)
    }
}
