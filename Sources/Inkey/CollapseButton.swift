import AppKit

/// Fixed vector geometry avoids symbol metrics and native blue push-button feedback.
final class CollapseButton: ToolButton {
    override var isFlipped: Bool { false }
    var collapsed = false { didSet { needsDisplay = true } }
    static func chevronPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -5, y: 2.5))
        path.addLine(to: CGPoint(x: 0, y: -2.5))
        path.addLine(to: CGPoint(x: 5, y: 2.5))
        return path
    }
    override func highlight(_ flag: Bool) { super.highlight(false) }
    override func performClick(_ sender: Any?) {
        guard isEnabled, let action else { return }
        // Manual tracking already handles the press; avoid NSButton's simulated press delay.
        sendAction(action, to: target)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext.current!.cgContext
        context.translateBy(x: bounds.midX, y: bounds.midY)
        if collapsed { context.rotate(by: .pi) }
        context.addPath(Self.chevronPath())
        context.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
        context.setLineWidth(1.5); context.setLineCap(.round); context.setLineJoin(.round)
        context.strokePath()
        NSGraphicsContext.restoreGraphicsState()
    }
}
