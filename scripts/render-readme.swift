import AppKit

/// Renders the real AppKit window and canvas offscreen with a non-personal example.
/// Build with README_ASSETS; this helper is excluded from the application target.
enum DocumentationRenderer {
    static func render() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let controller = InkeyApp()
        controller.buildWindow()
        controller.canvas.onChange = nil
        controller.canvas.onToolChange = nil
        controller.window.setFrame(NSRect(x: 100, y: 100, width: 920, height: 640), display: false)
        controller.layoutPalette(initial: true)

        let graphite = InkColor("303735")
        let muted = InkColor("7A817C")
        let green = InkColor("3E795E")
        let blue = InkColor("327BB3")
        var draft = Draft()
        draft.name = "Two pointers"
        draft.anchor = InkPoint(NSPoint(x: -100000, y: -100000))
        draft.background = InkColor("FAF9F6")
        func text(_ value: String, _ x: Double, _ y: Double, _ color: InkColor = graphite, size: Double = 20) -> InkItem {
            InkItem(kind: .text, points: [InkPoint(NSPoint(x: x, y: y))], color: color, text: value, fontSize: size)
        }
        func arrow(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: InkColor) -> InkItem {
            InkItem(kind: .arrow, points: [InkPoint(NSPoint(x: x1, y: y1)), InkPoint(NSPoint(x: x2, y: y2))], color: color)
        }
        func ring(_ x: Double, _ y: Double, _ color: InkColor) -> InkItem {
            let points = (0...80).map { index -> InkPoint in
                let angle = Double(index) / 80 * 2 * .pi
                let irregularity = 1 + 0.018 * sin(angle * 3) + 0.012 * cos(angle * 5)
                return InkPoint(NSPoint(x: x + 41 * cos(angle) * irregularity, y: y + 34 * sin(angle) * irregularity))
            }
            return InkItem(kind: .stroke, points: points, color: color, lineWidth: 2.5)
        }
        draft.items = [
            text("Two pointers, one answer.", 90, 85, size: 25),
            text("nums = [2, 7, 11, 15]    target = 9", 90, 132, muted, size: 17),
            text("0", 187, 205, muted, size: 14),
            text("1", 357, 205, muted, size: 14),
            text("2", 527, 205, muted, size: 14),
            text("3", 697, 205, muted, size: 14),
            text("2", 180, 247, green, size: 28),
            text("7", 350, 247, blue, size: 28),
            text("11", 510, 247, size: 28),
            text("15", 680, 247, size: 28),
            ring(190, 265, green), ring(360, 265, blue),
            arrow(190, 340, 190, 308, green), arrow(360, 340, 360, 308, blue),
            text("left", 165, 355, green, size: 18),
            text("right", 327, 355, blue, size: 18),
            arrow(700, 420, 370, 420, blue),
            text("move right inward", 450, 443, blue, size: 17),
            text("2 + 7 = 9", 90, 475, green, size: 24),
            text("return [left, right]", 90, 514, muted, size: 17)
        ]
        controller.canvas.install(draft)
        controller.statusLabel.stringValue = "Two pointers"
        controller.palette.paperIsDark = false
        controller.palette.refreshAppearance()
        controller.palette.choose(0)
        controller.canvas.cursorTrailEnabled = false

        guard let root = controller.window.contentView?.superview else { fatalError("Missing window frame") }
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("Cannot allocate preview") }
        root.cacheDisplay(in: root.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode preview") }
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/assets/inkey-canvas.png")
        do { try data.write(to: output, options: .atomic) }
        catch { fatalError("Cannot save preview: \(error)") }
        print("Rendered native Inkey example: \(bitmap.pixelsWide) × \(bitmap.pixelsHigh), \(data.count) bytes")
    }
}
