import AppKit

struct InkColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(_ hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x303333
        red = Double((value >> 16) & 255) / 255
        green = Double((value >> 8) & 255) / 255
        blue = Double(value & 255) / 255
    }

    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? .black
        red = rgb.redComponent; green = rgb.greenComponent; blue = rgb.blueComponent
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var hex: String { String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())) }
    static let light = ["303735", "C84D45", "A86F16", "3E795E", "327BB3", "8062AD"].map(InkColor.init)
    static let dark = ["E4E6E1", "F48B7F", "E7BC6F", "8DC3A2", "86BCE8", "BEA5E3"].map(InkColor.init)
    static func parse(_ text: String) -> InkColor? {
        let hex = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return InkColor(hex)
    }
}

struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ point: NSPoint) { x = point.x; y = point.y }
    var point: NSPoint { NSPoint(x: x, y: y) }
}

enum InkKind: String, Codable { case stroke, arrow, line, square, rectangle, ellipse, text, image }

struct InkItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: InkKind
    var points: [InkPoint]
    var color: InkColor
    var text = ""
    var fontSize: Double = 20
    var lineWidth: Double = 2.5
    var imageData: Data? = nil
    var imageWidth: Double = 0
    var imageHeight: Double = 0

    var outline: [InkPoint] {
        guard let a = points.first, let b = points.last else { return [] }
        switch kind {
        case .line: return [a, b]
        case .rectangle:
            return [a, InkPoint(NSPoint(x: b.x, y: a.y)), b, InkPoint(NSPoint(x: a.x, y: b.y)), a]
        case .square:
            let side = max(abs(b.x - a.x), abs(b.y - a.y))
            let x = a.x + (b.x < a.x ? -side : side), y = a.y + (b.y < a.y ? -side : side)
            return [a, InkPoint(NSPoint(x: x, y: a.y)), InkPoint(NSPoint(x: x, y: y)), InkPoint(NSPoint(x: a.x, y: y)), a]
        case .ellipse:
            let rx = abs(b.x - a.x) / 2, ry = abs(b.y - a.y) / 2
            return (0...180).map { index in
                let t = Double(index) * .pi / 90
                return InkPoint(NSPoint(x: (a.x + b.x) / 2 + rx * cos(t), y: (a.y + b.y) / 2 + ry * sin(t)))
            }
        default: return points
        }
    }

    var bounds: NSRect {
        guard let first = points.first?.point else { return .zero }
        if kind == .text {
            return NSRect(origin: first, size: InkTypography.size(text, fontSize: fontSize))
        }
        if kind == .image { return NSRect(x: first.x, y: first.y, width: imageWidth, height: imageHeight) }
        let xs = outline.map(\.x), ys = outline.map(\.y)
        return NSRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    mutating func translate(x: Double, y: Double) {
        points = points.map { InkPoint(NSPoint(x: $0.x + x, y: $0.y + y)) }
    }

    func hit(_ point: NSPoint, tolerance: CGFloat) -> Bool {
        guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
        if kind == .text || kind == .image { return true }
        var vertices = outline.map(\.point)
        if kind == .arrow, vertices.count > 1 { vertices = [vertices[0], vertices.last!] }
        if vertices.count == 1 { return hypot(point.x - vertices[0].x, point.y - vertices[0].y) <= tolerance }
        for (a, b) in zip(vertices, vertices.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length)) : 0
            if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance { return true }
        }
        return false
    }
}

struct Draft: Codable, Equatable {
    var version = 1
    var id = UUID()
    var name = "Untitled"
    var modified = Date()
    var items: [InkItem] = []
    var background = InkColor("FAF9F6")
    var zoom: Double = 1
    var offset = InkPoint(.zero)
    var anchor = InkPoint(NSPoint(x: 340, y: 220))
}

final class DraftStore {
    let directory: URL
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Inkey/Drafts", isDirectory: true)
    }

    func save(_ draft: Draft, to url: URL? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url ?? directory.appendingPathComponent("\(draft.id).inkey")
        try encoder.encode(draft).write(to: target, options: .atomic)
    }

    func load(_ url: URL) throws -> Draft {
        let draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: url))
        guard draft.version == 1 else { throw CocoaError(.fileReadUnknown) }
        guard draft.zoom.isFinite, (0.1...8).contains(draft.zoom),
              draft.offset.x.isFinite, draft.offset.y.isFinite,
              draft.anchor.x.isFinite, draft.anchor.y.isFinite,
              [draft.background.red, draft.background.green, draft.background.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              draft.items.allSatisfy({ item in
                  item.points.count > 0 && item.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) &&
                  item.fontSize.isFinite && (6...200).contains(item.fontSize) &&
                  item.lineWidth.isFinite && (0.1...100).contains(item.lineWidth) &&
                  [item.color.red, item.color.green, item.color.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) &&
                  item.imageWidth.isFinite && item.imageHeight.isFinite && item.imageWidth >= 0 && item.imageHeight >= 0
              }) else { throw CocoaError(.fileReadCorruptFile) }
        return draft
    }

    func recent() -> [(URL, Draft)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "inkey" }.compactMap { url in
            guard let draft = try? load(url) else { return nil }
            return (url, draft)
        }.sorted { $0.1.modified > $1.1.modified }
    }
}
