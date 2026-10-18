import AppKit

/// Track in the view directly so movement never waits for a system drag session.
class ReorderButton: NSButton {
    var reorderGroup: String?
    var onReorderBegin: ((NSPoint) -> Void)?
    var onReorderMove: ((NSPoint) -> Void)?
    var onReorderEnd: ((NSPoint) -> Void)?
    private var pressLocation: NSPoint?
    private var reordering = false

    override func mouseDown(with event: NSEvent) {
        guard reorderGroup != nil, !event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event); return
        }
        pressLocation = event.locationInWindow
        reordering = false
        highlight(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressLocation else { return }
        if !reordering {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
            reordering = true; highlight(false)
            onReorderBegin?(start)
        }
        onReorderMove?(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard reorderGroup != nil else { super.mouseUp(with: event); return }
        let clicked = pressLocation != nil && !reordering && bounds.contains(convert(event.locationInWindow, from: nil))
        pressLocation = nil; highlight(false)
        if reordering { reordering = false; onReorderEnd?(event.locationInWindow) }
        else if clicked { performClick(nil) }
    }
}
