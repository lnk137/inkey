import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Deterministic demonstrations built from the native canvas, without user drafts.
enum DocumentationFlows {
    private final class PointerOverlay: NSView {
        var point = NSPoint(x: 100, y: 100)
        var cue = ""
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let cursor = NSBezierPath()
            if cue == "Typing" {
                cursor.move(to: NSPoint(x: point.x, y: point.y - 10))
                cursor.line(to: NSPoint(x: point.x, y: point.y + 10))
            } else {
                cursor.move(to: NSPoint(x: point.x - 7, y: point.y))
                cursor.line(to: NSPoint(x: point.x + 7, y: point.y))
                cursor.move(to: NSPoint(x: point.x, y: point.y - 7))
                cursor.line(to: NSPoint(x: point.x, y: point.y + 7))
            }
            NSColor.white.setStroke(); cursor.lineWidth = 3.5; cursor.stroke()
            NSColor(calibratedWhite: 0.16, alpha: 0.9).setStroke(); cursor.lineWidth = 1.25; cursor.stroke()
            guard !cue.isEmpty else { return }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1)]
            let size = (cue as NSString).size(withAttributes: attributes)
            let frame = NSRect(x: 730, y: 52, width: max(120, size.width + 22), height: 26)
            NSColor(calibratedWhite: 1, alpha: 0.93).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
            NSColor(calibratedWhite: 0.83, alpha: 1).setStroke()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).stroke()
            (cue as NSString).draw(at: NSPoint(x: frame.minX + 11, y: frame.minY + 6), withAttributes: attributes)
        }
    }

    static func render() {
        let suite = "InkeyReadmeFlows.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = InkeyApp(preferences: UserPreferences(defaults: defaults))
        app.buildWindow()
        app.canvas.onChange = nil; app.canvas.onToolChange = nil
        app.window.setFrame(NSRect(x: 100, y: 100, width: 920, height: 640), display: false)
        app.layoutPalette(initial: true)
        app.canvas.cursorTrailEnabled = false
        let overlay = PointerOverlay(frame: app.window.contentView!.bounds)
        overlay.autoresizingMask = [.width, .height]
        app.window.contentView!.addSubview(overlay)
        let root = app.window.contentView!.superview!
        let graphite = InkColor("303735"), muted = InkColor("7A817C")
        let green = InkColor("3E795E"), blue = InkColor("327BB3"), orange = InkColor("C36A44")
        func itemText(_ value: String, _ x: Double, _ y: Double, _ color: InkColor = graphite, _ size: Double = 18) -> InkItem {
            InkItem(kind: .text, points: [InkPoint(NSPoint(x: x, y: y))], color: color, text: value, fontSize: size)
        }
        func shape(_ kind: InkKind, _ a: NSPoint, _ b: NSPoint, _ color: InkColor) -> InkItem {
            InkItem(kind: kind, points: [InkPoint(a), InkPoint(b)], color: color, lineWidth: 2.5)
        }
        func stroke(_ points: [NSPoint], _ color: InkColor) -> InkItem {
            InkItem(kind: .stroke, points: points.map(InkPoint.init), color: color, lineWidth: 2.5)
        }
        func output(_ name: String, frames: [(Draft, UUID?, NSPoint, String)], contrast: Bool = false, delay: Double = 0.11) {
            let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/assets/" + name)
            guard let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { fatalError("Cannot create animation") }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            app.canvas.setHighContrast(contrast, animated: false); app.palette.highContrastEnabled = contrast
            for (draft, selection, point, cue) in frames {
                if cue == "⇧ Drag · Arrow" { app.palette.chooseShape(.arrow) }
                if cue == "⇧ Drag · Rectangle" { app.palette.chooseShape(.rectangle) }
                app.canvas.install(draft); app.canvas.selection = selection
                overlay.point = point; overlay.cue = cue; overlay.needsDisplay = true
                app.canvas.needsDisplay = true; root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
                guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { fatalError("Cannot capture frame") }
                root.cacheDisplay(in: root.bounds, to: rep)
                guard let cg = rep.cgImage, let context = CGContext(data: nil, width: 920, height: 640, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot allocate frame") }
                context.interpolationQuality = .high; context.draw(cg, in: CGRect(x: 0, y: 0, width: 920, height: 640))
                guard let frame = context.makeImage() else { fatalError("Cannot create frame") }
                CGImageDestinationAddImage(dest, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(dest) else { fatalError("Cannot finish animation") }
            print("Rendered \(name): \(frames.count) frames")
        }
        func sampleImage() -> Data {
            let image = NSImage(size: NSSize(width: 250, height: 162), flipped: true) { rect in
                NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.95, alpha: 1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
                let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(calibratedRed: 0.22, green: 0.33, blue: 0.28, alpha: 1)]
                ("TRAINING LOSS" as NSString).draw(at: NSPoint(x: 17, y: 15), withAttributes: title)
                NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
                let axes = NSBezierPath(); axes.lineWidth = 1; axes.move(to: NSPoint(x: 28, y: 45)); axes.line(to: NSPoint(x: 28, y: 132)); axes.line(to: NSPoint(x: 222, y: 132)); axes.stroke()
                let curve = NSBezierPath(); curve.lineWidth = 3; curve.lineCapStyle = .round
                curve.move(to: NSPoint(x: 30, y: 53)); curve.curve(to: NSPoint(x: 220, y: 118), controlPoint1: NSPoint(x: 55, y: 112), controlPoint2: NSPoint(x: 140, y: 115))
                NSColor(calibratedRed: 0.24, green: 0.47, blue: 0.37, alpha: 1).setStroke(); curve.stroke()
                return true
            }
            return image.tiffRepresentation!
        }
        var base = Draft(); base.name = "Deep learning notes"; base.background = InkColor("FAF9F6"); base.anchor = InkPoint(NSPoint(x: -100000, y: -100000))
        app.statusLabel.stringValue = base.name
        let heading = itemText("Neural networks", 70, 76, graphite, 27)
        let subtitle = itemText("Forward pass & training", 70, 119, muted, 16)
        let forward = itemText("1. Forward pass", 70, 185, green, 18)
        let equation = itemText("y = f(x; θ)", 70, 220, graphite, 23)
        let update = itemText("2. Gradient descent", 70, 342, blue, 18)
        let updateEquation = itemText("θ ← θ − η∇L", 70, 380, graphite, 22)
        let rectangle = shape(.rectangle, NSPoint(x: 57, y: 369), NSPoint(x: 300, y: 420), orange)
        let arrow = shape(.arrow, NSPoint(x: 265, y: 238), NSPoint(x: 455, y: 238), blue)
        let image = InkItem(kind: .image, points: [InkPoint(NSPoint(x: 555, y: 195))], color: graphite, imageData: sampleImage(), imageWidth: 250, imageHeight: 162)
        let underline = stroke((0...22).map { i in NSPoint(x: 71 + Double(i) * 7, y: 260 + 1.5 * sin(Double(i) / 4)) }, green)
        var frames: [(Draft, UUID?, NSPoint, String)] = []
        var work = base
        func append(_ d: Draft, _ selection: UUID? = nil, _ point: NSPoint, _ cue: String, repeat count: Int = 1) {
            for _ in 0..<count { frames.append((d, selection, point, cue)) }
        }
        // Reveal each text item one character at a time, with the caret at the text's current width.
        func type(_ item: InkItem) {
            for count in 0...item.text.count {
                var frame = work
                var partial = item; partial.text = String(item.text.prefix(count))
                frame.items.append(partial)
                let width = count == 0 ? 0 : InkTypography.size(partial.text, fontSize: partial.fontSize).width
                let position = item.points[0].point
                append(frame, nil, NSPoint(x: position.x + width, y: position.y + item.fontSize * 0.6), "Typing")
            }
            work.items.append(item)
        }
        type(heading)
        type(subtitle)
        type(forward)
        type(equation)
        for n in 2...22 { var frame = work; var partial = underline; partial.points = Array(underline.points.prefix(n)); frame.items.append(partial); append(frame, nil, partial.points.last!.point, "Draw") }
        work.items.append(underline)
        for n in 0...12 { var frame = work; var a = arrow; a.points[1] = InkPoint(NSPoint(x: 265 + 190 * Double(n) / 12, y: 238)); frame.items.append(a); append(frame, nil, a.points[1].point, "⇧ Drag · Arrow") }
        work.items.append(arrow)
        type(update)
        type(updateEquation)
        for n in 0...10 { var frame = work; var b = rectangle; b.points[1] = InkPoint(NSPoint(x: 57 + 243 * Double(n) / 10, y: 369 + 51 * Double(n) / 10)); frame.items.append(b); append(frame, nil, b.points[1].point, "⇧ Drag · Rectangle") }
        work.items += [rectangle]
        append(work, nil, NSPoint(x: 650, y: 280), "⌘ V", repeat: 4)
        work.items += [image]
        append(work, nil, NSPoint(x: 650, y: 280), "⌘ V", repeat: 12)
        let completed = work
        output("inkey-note-flow.gif", frames: frames, delay: 0.08)

        // Continue from the exact completed note and apply the production resize gestures.
        frames = []
        let textIndex = completed.items.firstIndex { $0.id == equation.id }!
        let shapeIndex = completed.items.firstIndex { $0.id == rectangle.id }!
        let imageIndex = completed.items.firstIndex { $0.id == image.id }!
        let bounds = InkTypography.displayBounds(for: equation)
        let textStart = TextResizeCorner.bottomRight.point(in: bounds)
        let textResize = TextResizeGesture(items: completed.items, item: equation, corner: .bottomRight, start: textStart)
        append(work, equation.id, textStart, "Right-click · text", repeat: 4)
        for n in 0...10 { var frame = work; frame.items[textIndex] = textResize.resized(to: NSPoint(x: textStart.x + Double(n) * 3, y: textStart.y + Double(n))); append(frame, equation.id, NSPoint(x: textStart.x + Double(n) * 3, y: textStart.y + Double(n)), "Resize text") }
        work.items[textIndex] = textResize.resized(to: NSPoint(x: textStart.x + 30, y: textStart.y + 10))
        let shapeStart = TextResizeCorner.bottomRight.point(in: rectangle.shapeGeometry)
        let shapeResize = ShapeResizeGesture(items: work.items, item: rectangle, corner: .bottomRight, start: shapeStart)
        append(work, rectangle.id, shapeStart, "Right-click · shape", repeat: 4)
        for n in 0...10 { var frame = work; frame.items[shapeIndex] = shapeResize.resized(to: NSPoint(x: shapeStart.x + Double(n) * 3, y: shapeStart.y + Double(n))); append(frame, rectangle.id, NSPoint(x: shapeStart.x + Double(n) * 3, y: shapeStart.y + Double(n)), "Resize shape") }
        work.items[shapeIndex] = shapeResize.resized(to: NSPoint(x: shapeStart.x + 30, y: shapeStart.y + 10))
        let imageStart = TextResizeCorner.bottomRight.point(in: image.bounds)
        let imageResize = ImageResizeGesture(items: work.items, item: image, corner: .bottomRight, start: imageStart)
        append(work, image.id, imageStart, "Right-click · image", repeat: 4)
        for n in 0...10 { var frame = work; frame.items[imageIndex] = imageResize.resized(to: NSPoint(x: imageStart.x + Double(n) * 3, y: imageStart.y + Double(n) * 2)); append(frame, image.id, NSPoint(x: imageStart.x + Double(n) * 3, y: imageStart.y + Double(n) * 2), "Resize image") }
        work.items[imageIndex] = imageResize.resized(to: NSPoint(x: imageStart.x + 30, y: imageStart.y + 20))
        append(work, nil, NSPoint(x: 850, y: 460), "", repeat: 12)
        output("inkey-adjust-flow.gif", frames: frames)

        // Synthetic course page with native high-contrast annotations, not a personal screen.
        let page = NSImage(size: NSSize(width: 920, height: 640), flipped: true) { rect in
            NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.95, alpha: 1).setFill(); rect.fill()
            NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: 42, y: 45, width: 836, height: 550), xRadius: 12, yRadius: 12).fill()
            func label(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) {
                (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
            }
            let dark = NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.18, alpha: 1), dim = NSColor(calibratedWhite: 0.48, alpha: 1)
            label("learn.example.org  /  DEEP LEARNING  /  03", 78, 75, 11, dim, .semibold)
            label("How neural networks learn", 78, 112, 27, dark, .semibold)
            label("Lesson 03   ·   Gradient descent", 78, 155, 14, dim)
            NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.16, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 78, y: 208, width: 485, height: 264), xRadius: 10, yRadius: 10).fill()
            label("LOSS FUNCTION", 105, 236, 12, NSColor(calibratedWhite: 0.72, alpha: 1), .semibold)
            let axis = NSBezierPath(); axis.lineWidth = 1; axis.move(to: NSPoint(x: 130, y: 278)); axis.line(to: NSPoint(x: 130, y: 416)); axis.line(to: NSPoint(x: 510, y: 416)); NSColor(calibratedWhite: 0.55, alpha: 1).setStroke(); axis.stroke()
            let curve = NSBezierPath(); curve.lineWidth = 3; curve.move(to: NSPoint(x: 150, y: 290)); curve.curve(to: NSPoint(x: 485, y: 392), controlPoint1: NSPoint(x: 190, y: 380), controlPoint2: NSPoint(x: 270, y: 390)); NSColor(calibratedRed: 0.49, green: 0.75, blue: 0.62, alpha: 1).setStroke(); curve.stroke()
            label("Gradient descent", 595, 225, 19, dark, .semibold)
            label("Update the weights in the", 595, 265, 14, dim)
            label("direction that reduces loss.", 595, 289, 14, dim)
            label("θ ← θ − η∇L", 595, 335, 19, dark)
            label("NEXT  /  BACKPROPAGATION", 78, 515, 11, dim, .semibold)
            return true
        }
        let background = InkItem(kind: .image, points: [InkPoint(.zero)], color: graphite, imageData: page.tiffRepresentation!, imageWidth: 920, imageHeight: 640)
        var screen = base; screen.name = "Screen draft"; screen.items = [background]
        app.statusLabel.stringValue = screen.name
        frames = []
        let yellow = InkColor("F5CC70")
        let note = itemText("smaller loss", 225, 302, yellow, 20)
        for n in 0...note.text.count { var d = screen; var partial = note; partial.text = String(note.text.prefix(n)); d.items.append(partial); append(d, nil, NSPoint(x: 230 + Double(n) * 9, y: 316), "Type on screen") }
        screen.items.append(note)
        let mark = shape(.arrow, NSPoint(x: 330, y: 345), NSPoint(x: 416, y: 389), yellow)
        for n in 0...12 { var d = screen; var a = mark; a.points[1] = InkPoint(NSPoint(x: 330 + Double(n) * 86 / 12, y: 345 + Double(n) * 44 / 12)); d.items.append(a); append(d, nil, a.points[1].point, "Draw on screen") }
        screen.items.append(mark)
        let second = itemText("step size = η", 595, 385, green, 17)
        for n in 0...second.text.count { var d = screen; var partial = second; partial.text = String(second.text.prefix(n)); d.items.append(partial); append(d, nil, NSPoint(x: 600 + Double(n) * 7, y: 400), "Type on screen") }
        screen.items.append(second); append(screen, nil, NSPoint(x: 800, y: 470), "", repeat: 14)
        output("inkey-screen-flow.gif", frames: frames, contrast: true)
    }
}
