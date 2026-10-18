import AppKit
import QuartzCore

/// Track in the view directly so movement never waits for a system drag session.
class ReorderButton: NSButton {
    var reorderGroup: String?
    var onReorderBegin: ((NSPoint) -> Void)?
    var onReorderMove: ((NSPoint) -> Void)?
    var onReorderEnd: ((NSPoint) -> Void)?
    var onToolbarMouseEvent: ((NSEvent) -> Void)?
    private var pressLocation: NSPoint?
    private var reordering = false
    var isTracking: Bool { pressLocation != nil }
    func cancelTracking() {
        pressLocation = nil; reordering = false; highlight(false)
    }

    /// Animate presentation only; hit testing and model geometry update immediately.
    func move(to origin: NSPoint, animated: Bool) {
        let previous = layer?.presentation()?.position ?? layer?.position
        layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            setFrameOrigin(origin)
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer, let previous, previous != layer.position else { return }
        let motion = CABasicAnimation(keyPath: "position")
        motion.fromValue = NSValue(point: previous); motion.toValue = NSValue(point: layer.position)
        motion.duration = 0.1; motion.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(motion, forKey: "palettePosition")
    }

    override func mouseDown(with event: NSEvent) {
        guard reorderGroup != nil || onToolbarMouseEvent != nil, !event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event); return
        }
        onToolbarMouseEvent?(event)
        pressLocation = event.locationInWindow
        reordering = false
        highlight(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressLocation else { return }
        if !reordering {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
            reordering = true; highlight(false)
            if onToolbarMouseEvent == nil { onReorderBegin?(start) }
        }
        if let onToolbarMouseEvent { onToolbarMouseEvent(event) }
        else { onReorderMove?(event.locationInWindow) }
    }

    override func mouseUp(with event: NSEvent) {
        guard reorderGroup != nil || onToolbarMouseEvent != nil else { super.mouseUp(with: event); return }
        let clicked = pressLocation != nil && !reordering && bounds.contains(convert(event.locationInWindow, from: nil))
        let dragged = reordering
        pressLocation = nil; highlight(false)
        reordering = false
        if let onToolbarMouseEvent { onToolbarMouseEvent(event) }
        else if dragged { onReorderEnd?(event.locationInWindow) }
        if clicked { performClick(nil) }
    }
}
