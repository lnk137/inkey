import AppKit

/// A pointer overlay, separate from draft rendering and exports.
final class EraserOutlineView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSColor.black.withAlphaComponent(0.6).setStroke()
        ring.lineWidth = 3; ring.stroke()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        ring.lineWidth = 1; ring.stroke()
    }
}
