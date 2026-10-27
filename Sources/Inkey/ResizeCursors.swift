import AppKit

extension TextResizeCorner {
    var resizeCursor: NSCursor { isLeft == isTop ? ResizeCursors.down : ResizeCursors.up }
}

private enum ResizeCursors {
    static let down = make(descending: true)
    static let up = make(descending: false)

    private static func make(descending: Bool) -> NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: descending ? .topLeft : .topRight, directions: .all)
        }
        // AppKit added diagonal frame cursors in macOS 15. Draw a compact
        // high-contrast double arrow for the supported macOS 14 fallback.
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: descending ? x : 24 - x, y: y) }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}
