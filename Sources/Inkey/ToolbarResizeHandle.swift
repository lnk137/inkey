import AppKit

final class ToolbarResizeHandle: NSView {
    var onBegin: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onEnd: (() -> Void)?
    var onReset: (() -> Void)?
    private var tracking = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = localized("ui.drag_horizontally_to_resize_toolbar_double_click_to_reset")
        setAccessibilityElement(true); setAccessibilityRole(.handle)
        setAccessibilityLabel(localized("ui.resize_toolbar"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setStroke()
        let arrows = NSBezierPath(); arrows.lineWidth = 1; arrows.lineCapStyle = .round; arrows.lineJoinStyle = .round
        arrows.move(to: NSPoint(x: 5, y: 10)); arrows.line(to: NSPoint(x: 17, y: 10))
        arrows.move(to: NSPoint(x: 8, y: 13)); arrows.line(to: NSPoint(x: 5, y: 10)); arrows.line(to: NSPoint(x: 8, y: 7))
        arrows.move(to: NSPoint(x: 14, y: 13)); arrows.line(to: NSPoint(x: 17, y: 10)); arrows.line(to: NSPoint(x: 14, y: 7))
        arrows.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?(); return }
        onBegin?(event.locationInWindow); tracking = true
    }
    override func mouseDragged(with event: NSEvent) {
        if tracking { onDrag?(event.locationInWindow) }
    }
    override func mouseUp(with event: NSEvent) {
        guard tracking else { return }
        onDrag?(event.locationInWindow); tracking = false; onEnd?()
    }
    func cancelTracking() { tracking = false }
}
