import AppKit

enum TextResizeCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
    func point(in rect: NSRect) -> NSPoint { NSPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.minY : rect.maxY) }
}

struct TextResizeGesture {
    let items: [InkItem]
    let item: InkItem
    let corner: TextResizeCorner
    let start: NSPoint
    var textTracking: CGFloat = 0

    func resized(to point: NSPoint) -> InkItem {
        let bounds = InkTypography.displayBounds(for: item, tracking: textTracking)
        let vx = (corner.isLeft ? -1.0 : 1.0) * bounds.width
        let vy = (corner.isTop ? -1.0 : 1.0) * bounds.height
        let length = vx * vx + vy * vy
        let scale = 1 + ((point.x - start.x) * vx + (point.y - start.y) * vy) / max(1, length)
        var result = item
        result.fontSize = min(200, max(6, item.fontSize * scale))
        let size = InkTypography.size(item.text, fontSize: result.fontSize, tracking: textTracking)
        let raw = InkTypography.size(item.text, fontSize: result.fontSize)
        let fixed = TextResizeCorner.allCases.first { $0.isLeft != corner.isLeft && $0.isTop != corner.isTop }!.point(in: bounds)
        result.points[0] = InkPoint(NSPoint(x: (corner.isLeft ? fixed.x - size.width : fixed.x) + (size.width - raw.width) / 2, y: corner.isTop ? fixed.y - size.height : fixed.y))
        return result
    }
}
