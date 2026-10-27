import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the real AppKit window and canvas offscreen with a non-personal example.
/// Build with README_ASSETS; this helper is excluded from the application target.
enum DocumentationRenderer {
    static func render() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let suite = "InkeyReadme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = InkeyApp(preferences: UserPreferences(defaults: defaults))
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

        // A selection and resize demonstration uses the same canvas and geometry as the app.
        func snapshot() -> NSBitmapImageRep {
            controller.canvas.needsDisplay = true
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
            guard let image = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("Cannot allocate screenshot") }
            root.cacheDisplay(in: root.bounds, to: image)
            return image
        }
        func save(_ image: NSBitmapImageRep, as filename: String) {
            guard let bytes = image.representation(using: .png, properties: [:]) else { fatalError("Cannot encode screenshot") }
            try! bytes.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/assets/" + filename), options: .atomic)
        }
        func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: InkColor) -> InkItem {
            InkItem(kind: .rectangle, points: [InkPoint(NSPoint(x: x, y: y)), InkPoint(NSPoint(x: x + width, y: y + height))], color: color, lineWidth: 3)
        }
        let terracotta = InkColor("C36A44")
        let selected = box(332, 243, 190, 98, green)
        draft.name = "A little system"
        draft.items = [
            text("Make the idea visible.", 90, 85, size: 25),
            text("Sketch a flow. Adjust it as it takes shape.", 90, 132, muted, size: 16),
            box(90, 243, 160, 98, blue), selected, box(690, 243, 160, 98, terracotta),
            text("capture", 125, 278, blue, size: 18),
            text("connect", 367, 278, green, size: 18),
            text("refine", 730, 278, terracotta, size: 18),
            arrow(264, 292, 318, 292, muted), arrow(596, 292, 676, 292, muted),
            text("A sketch can keep up with the thought.", 90, 430, muted, size: 17)
        ]
        controller.canvas.install(draft)
        controller.canvas.selection = selected.id
        controller.statusLabel.stringValue = draft.name
        save(snapshot(), as: "inkey-shape-selection.png")

        // Capture real resize geometry as a short, looping GIF. The anchor is fixed.
        let destinationURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/assets/inkey-resize.gif")
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.gif.identifier as CFString, 26, nil) else { fatalError("Cannot create GIF") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let resize = ShapeResizeGesture(items: draft.items, item: selected, corner: .bottomRight, start: NSPoint(x: 522, y: 341))
        let phases = Array(repeating: 0.0, count: 3) + (1...10).map { Double($0) / 10 } + Array(repeating: 1.0, count: 3) + (1...10).map { 1 - Double($0) / 10 }
        for phase in phases {
            let eased = phase * phase * (3 - 2 * phase)
            var frame = draft
            let changed = resize.resized(to: NSPoint(x: 522 + 60 * eased, y: 341 + 48 * eased))
            frame.items[3] = changed
            controller.canvas.install(frame); controller.canvas.selection = changed.id
            let image = snapshot()
            guard let cgImage = image.cgImage, let context = CGContext(data: nil, width: 920, height: 640, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot allocate GIF frame") }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 920, height: 640))
            guard let frameImage = context.makeImage() else { fatalError("Cannot capture GIF frame") }
            CGImageDestinationAddImage(destination, frameImage, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.09]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finish GIF") }

        // A synthetic browser-like background avoids capturing personal windows or drafts.
        let page = NSImage(size: NSSize(width: 920, height: 640), flipped: true) { rect in
            NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); rect.fill()
            NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 45, y: 46, width: 830, height: 545), xRadius: 12, yRadius: 12).fill()
            func label(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) {
                (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }
            let dark = NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.19, alpha: 1)
            let secondary = NSColor(calibratedWhite: 0.48, alpha: 1)
            label("WORKSPACE  /  NOTES", 88, 82, 11, secondary, .semibold)
            label("A better way to think it through", 88, 125, 27, dark, .semibold)
            label("A small problem, a blank space, and room to work.", 88, 170, 15, secondary)
            NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.17, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 88, y: 224, width: 744, height: 204), xRadius: 10, yRadius: 10).fill()
            let code = NSColor(calibratedRed: 0.81, green: 0.86, blue: 0.83, alpha: 1)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), .foregroundColor: code]
            for (i, line) in ["let values = [2, 7, 11, 15]", "let target = 9", "", "for value in values {", "    // explore the relationship", "}"].enumerated() {
                (line as NSString).draw(at: NSPoint(x: 116, y: 253 + CGFloat(i) * 25), withAttributes: attrs)
            }
            label("Notes", 88, 465, 14, secondary, .semibold)
            label("Keep the context in view while you sketch.", 88, 492, 15, secondary)
            return true
        }
        guard let pageData = page.tiffRepresentation else { fatalError("Cannot create synthetic backdrop") }
        let backdrop = InkItem(kind: .image, points: [InkPoint(.zero)], color: graphite, imageData: pageData, imageWidth: 920, imageHeight: 640)
        draft.name = "Screen draft"
        draft.items = [backdrop,
            text("2 + 7 = 9", 490, 282, InkColor("F3C46B"), size: 26),
            arrow(465, 330, 385, 373, InkColor("F3C46B")),
            text("try the pair", 478, 360, InkColor("F3C46B"), size: 18)]
        controller.canvas.install(draft)
        controller.canvas.setHighContrast(true, animated: false)
        controller.palette.highContrastEnabled = true
        controller.statusLabel.stringValue = "Screen draft"
        save(snapshot(), as: "inkey-screen-draft.png")

    }
}
