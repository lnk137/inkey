import AppKit

struct ImageResizeGesture {
    let items: [InkItem]
    let item: InkItem
    let corner: TextResizeCorner
    let start: NSPoint

    func resized(to point: NSPoint) -> InkItem {
        let rect = item.bounds
        let vx = (corner.isLeft ? -1.0 : 1.0) * rect.width
        let vy = (corner.isTop ? -1.0 : 1.0) * rect.height
        let proposed = 1 + ((point.x - start.x) * vx + (point.y - start.y) * vy) / max(1, vx * vx + vy * vy)
        let longest = max(rect.width, rect.height)
        let scale = min(10000 / max(1, longest), max(24 / max(1, longest), proposed))
        var result = item
        result.imageWidth = rect.width * scale
        result.imageHeight = rect.height * scale
        let fixed = NSPoint(x: corner.isLeft ? rect.maxX : rect.minX, y: corner.isTop ? rect.maxY : rect.minY)
        result.points[0] = InkPoint(NSPoint(x: corner.isLeft ? fixed.x - result.imageWidth : fixed.x, y: corner.isTop ? fixed.y - result.imageHeight : fixed.y))
        return result
    }
}
