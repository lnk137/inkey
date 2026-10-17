import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Inkey.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let paper = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
        NSColor(srgbRed: 0.96, green: 0.95, blue: 0.91, alpha: 1).setFill(); paper.fill()
        let ink = NSColor(srgbRed: 0.17, green: 0.22, blue: 0.20, alpha: 1)
        ink.setStroke(); ink.setFill()
        // One continuous handwritten stroke: a compact mark with a forward flick.
        let path = NSBezierPath(); path.lineWidth = 72; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: NSPoint(x: 390, y: 555))
        path.curve(to: NSPoint(x: 415, y: 290), controlPoint1: NSPoint(x: 320, y: 400), controlPoint2: NSPoint(x: 305, y: 270))
        path.curve(to: NSPoint(x: 695, y: 590), controlPoint1: NSPoint(x: 525, y: 315), controlPoint2: NSPoint(x: 620, y: 480))
        path.stroke()
        NSBezierPath(ovalIn: NSRect(x: 390, y: 670, width: 85, height: 85)).fill()
        image.unlockFocus()
        let data = image.tiffRepresentation!
        let bitmap = NSBitmapImageRep(data: data)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
