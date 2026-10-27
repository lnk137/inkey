import AppKit

extension InkItem {
    var isTransformableShape: Bool {
        [.arrow, .line, .rectangle, .ellipse, .square].contains(kind)
    }

    var shapeGeometry: NSRect { bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2) }
    var usesEndpointHandles: Bool { kind == .arrow || kind == .line }

    func containsShape(_ point: NSPoint, tolerance: CGFloat) -> Bool {
        if hit(point, tolerance: tolerance) { return true }
        if kind == .rectangle || kind == .square { return shapeGeometry.contains(point) }
        if kind == .ellipse {
            let rect = shapeGeometry
            guard rect.width > 0, rect.height > 0 else { return false }
            let x = (point.x - rect.midX) / (rect.width / 2)
            let y = (point.y - rect.midY) / (rect.height / 2)
            return x * x + y * y <= 1
        }
        return false
    }
}

struct ShapeResizeGesture {
    let items: [InkItem]
    let item: InkItem
    let corner: TextResizeCorner
    let start: NSPoint
    var endpoint: Int? = nil

    private func signedSize(to point: NSPoint) -> NSSize {
        let rect = item.shapeGeometry
        let dx = (point.x - start.x) * (corner.isLeft ? -1 : 1)
        let dy = (point.y - start.y) * (corner.isTop ? -1 : 1)
        let width = min(10000, max(-10000, rect.width + dx))
        let height = min(10000, max(-10000, rect.height + dy))
        if item.kind == .square {
            let side = min(10000, max(-10000, rect.width + (dx + dy) / 2))
            return NSSize(width: side, height: side)
        }
        return NSSize(width: width, height: height)
    }

    func activeCorner(at point: NSPoint) -> TextResizeCorner {
        let size = signedSize(to: point)
        let left = size.width < 0 ? !corner.isLeft : corner.isLeft
        let top = size.height < 0 ? !corner.isTop : corner.isTop
        return TextResizeCorner.allCases.first { $0.isLeft == left && $0.isTop == top }!
    }

    func resized(to point: NSPoint) -> InkItem {
        if let endpoint {
            var result = item
            let original = item.points[endpoint]
            result.points[endpoint] = InkPoint(NSPoint(x: original.x + point.x - start.x, y: original.y + point.y - start.y))
            return result
        }
        let rect = item.shapeGeometry
        let size = signedSize(to: point)
        let width = size.width, height = size.height
        // A press without movement must never alter even a degenerate shape.
        if point == start { return item }
        let fixed = NSPoint(x: corner.isLeft ? rect.maxX : rect.minX,
                            y: corner.isTop ? rect.maxY : rect.minY)
        let origin = NSPoint(x: corner.isLeft ? fixed.x - width : fixed.x,
                             y: corner.isTop ? fixed.y - height : fixed.y)
        var result = item
        result.points = item.points.enumerated().map { index, p in
            // Preserve endpoint order, including legacy square geometry.
            let fallback = Double(index) / Double(max(1, item.points.count - 1))
            let tx = rect.width > 0 ? (p.x - rect.minX) / rect.width : fallback
            let ty = rect.height > 0 ? (p.y - rect.minY) / rect.height : fallback
            return InkPoint(NSPoint(x: origin.x + tx * width, y: origin.y + ty * height))
        }
        return result
    }
}
