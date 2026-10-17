import AppKit

/// Removes vector ink along a swept circular eraser without painting over the paper.
enum InkEraser {
    private typealias Interval = ClosedRange<Double>

    static func erase(_ items: [InkItem], from start: InkPoint, to end: InkPoint, radius: Double) -> [InkItem] {
        guard radius.isFinite, radius > 0 else { return items }
        return items.flatMap { item -> [InkItem] in
            switch item.kind {
            case .image: return [item]
            case .text:
                return intersects(item.bounds, start, end, radius) ? [] : [item]
            case .arrow:
                guard let first = item.points.first, let last = item.points.last else { return [item] }
                let angle = atan2(last.y - first.y, last.x - first.x)
                let length = min(13, max(6, hypot(last.x - first.x, last.y - first.y) * 0.25))
                let head1 = InkPoint(NSPoint(x: last.x - length * cos(angle - 0.48), y: last.y - length * sin(angle - 0.48)))
                let head2 = InkPoint(NSPoint(x: last.x - length * cos(angle + 0.48), y: last.y - length * sin(angle + 0.48)))
                let segments = [(first, last), (head1, last), (last, head2)]
                return segments.contains { !cuts($0.0, $0.1, start, end, radius + item.lineWidth / 2).isEmpty } ? [] : [item]
            case .line, .square, .ellipse:
                var stroke = item; stroke.kind = .stroke; stroke.points = item.outline
                let erased = split(stroke, start, end, radius + item.lineWidth / 2)
                return erased == [stroke] ? [item] : erased
            case .stroke:
                return split(item, start, end, radius + item.lineWidth / 2)
            }
        }
    }

    private static func split(_ item: InkItem, _ start: InkPoint, _ end: InkPoint, _ radius: Double) -> [InkItem] {
        guard item.points.count > 1 else {
            return item.points.first.map { distance($0, start, end) <= radius ? [] : [item] } ?? [item]
        }
        var fragments: [[InkPoint]] = [], run: [InkPoint] = []
        var touched = false
        func finish() {
            if run.count >= 2 { fragments.append(run) }
            run = []
        }
        for (a, b) in zip(item.points, item.points.dropFirst()) {
            let erased = cuts(a, b, start, end, radius)
            if erased.isEmpty {
                if run.isEmpty { run.append(a) }
                run.append(b)
                continue
            }
            touched = true
            var lower = 0.0
            for interval in erased {
                if interval.lowerBound > lower + 1e-9 {
                    let from = interpolate(a, b, lower), to = interpolate(a, b, interval.lowerBound)
                    if run.isEmpty { run.append(from) }
                    run.append(to)
                }
                finish()
                lower = max(lower, interval.upperBound)
            }
            if lower < 1 - 1e-9 { run = [interpolate(a, b, lower), b] }
        }
        finish()
        guard touched else { return [item] }
        return fragments.enumerated().map { index, points in
            var fragment = item
            if index > 0 { fragment.id = UUID() }
            fragment.points = points
            return fragment
        }
    }

    private static func interpolate(_ a: InkPoint, _ b: InkPoint, _ t: Double) -> InkPoint {
        InkPoint(NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }

    /// Clips a linear scalar to a closed interval, returning the valid parameter range.
    private static func linear(_ origin: Double, _ delta: Double, _ low: Double, _ high: Double) -> Interval? {
        if abs(delta) < 1e-12 { return (low...high).contains(origin) ? 0...1 : nil }
        let a = (low - origin) / delta, b = (high - origin) / delta
        let lower = max(0, min(a, b)), upper = min(1, max(a, b))
        return lower <= upper ? lower...upper : nil
    }

    private static func circle(_ a: InkPoint, _ b: InkPoint, _ center: InkPoint, _ radius: Double) -> Interval? {
        let dx = b.x - a.x, dy = b.y - a.y, x = a.x - center.x, y = a.y - center.y
        let aa = dx * dx + dy * dy
        if aa < 1e-18 { return hypot(x, y) <= radius ? 0...1 : nil }
        let bb = 2 * (x * dx + y * dy), cc = x * x + y * y - radius * radius
        let discriminant = bb * bb - 4 * aa * cc
        guard discriminant >= 0 else { return nil }
        let root = sqrt(discriminant)
        let lower = max(0, (-bb - root) / (2 * aa)), upper = min(1, (-bb + root) / (2 * aa))
        return lower <= upper ? lower...upper : nil
    }

    /// Intersection of a stroke segment with the capsule swept by an eraser gesture.
    private static func cuts(_ a: InkPoint, _ b: InkPoint, _ c: InkPoint, _ d: InkPoint, _ radius: Double) -> [Interval] {
        var intervals = [circle(a, b, c, radius), circle(a, b, d, radius)].compactMap { $0 }
        let ux = d.x - c.x, uy = d.y - c.y, lengthSquared = ux * ux + uy * uy
        if lengthSquared > 1e-18 {
            let vx = b.x - a.x, vy = b.y - a.y, x = a.x - c.x, y = a.y - c.y
            if let along = linear(x * ux + y * uy, vx * ux + vy * uy, 0, lengthSquared),
               let across = linear(x * uy - y * ux, vx * uy - vy * ux, -radius * sqrt(lengthSquared), radius * sqrt(lengthSquared)) {
                let lower = max(along.lowerBound, across.lowerBound), upper = min(along.upperBound, across.upperBound)
                if lower <= upper { intervals.append(lower...upper) }
            }
        }
        intervals.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Interval] = []
        for interval in intervals {
            if let previous = merged.last, interval.lowerBound <= previous.upperBound + 1e-9 {
                merged[merged.count - 1] = previous.lowerBound...max(previous.upperBound, interval.upperBound)
            } else { merged.append(interval) }
        }
        return merged
    }

    private static func distance(_ p: InkPoint, _ a: InkPoint, _ b: InkPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
        let t = squared > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    private static func intersects(_ rect: NSRect, _ a: InkPoint, _ b: InkPoint, _ radius: Double) -> Bool {
        if let x = linear(a.x, b.x - a.x, rect.minX, rect.maxX),
           let y = linear(a.y, b.y - a.y, rect.minY, rect.maxY),
           max(x.lowerBound, y.lowerBound) <= min(x.upperBound, y.upperBound) { return true }
        let corners = [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)]
        if corners.contains(where: { distance(InkPoint($0), a, b) <= radius }) { return true }
        return [a, b].contains { p in
            hypot(p.x - min(rect.maxX, max(rect.minX, p.x)), p.y - min(rect.maxY, max(rect.minY, p.y))) <= radius
        }
    }
}
