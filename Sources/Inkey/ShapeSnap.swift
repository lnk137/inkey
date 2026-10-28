import AppKit

/// Snap in screen-space so the interaction feels the same at every zoom level.
struct ShapeSnap {
    enum Alignment: Equatable { case horizontal, vertical, equalSides }
    private(set) var alignment: Alignment?

    mutating func point(from start: NSPoint, to end: NSPoint, kind: InkKind, zoom: CGFloat) -> NSPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let scale = max(zoom, 0.001)
        let threshold: CGFloat = (alignment == nil ? 6 : 10) / scale
        guard hypot(dx, dy) * scale >= 20 else { alignment = nil; return end }
        let candidate: Alignment?
        switch kind {
        case .arrow, .line:
            if abs(dy) <= threshold && abs(dx) > abs(dy) { candidate = .horizontal }
            else if abs(dx) <= threshold && abs(dy) > abs(dx) { candidate = .vertical }
            else { candidate = nil }
        case .rectangle, .ellipse:
            candidate = abs(abs(dx) - abs(dy)) / sqrt(2) <= threshold ? .equalSides : nil
        default: candidate = nil
        }
        alignment = candidate
        switch candidate {
        case .horizontal: return NSPoint(x: end.x, y: start.y)
        case .vertical: return NSPoint(x: start.x, y: end.y)
        case .equalSides:
            let side = (abs(dx) + abs(dy)) / 2
            return NSPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        case nil: return end
        }
    }
}
