import AppKit

/// One line grid for Latin, CJK fallback fonts, marked text, and committed ink.
final class InkTextLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var pointSize: CGFloat = 20
    var contrastStrength: () -> CGFloat = { 0 }
    var renderingScale: () -> CGFloat = { 1 }
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawContrast(forGlyphRange: glyphsToShow, at: origin)
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }
    func drawContrast(forGlyphRange range: NSRange, at origin: NSPoint) {
        let strength = contrastStrength()
        guard strength > 0, let storage = textStorage, storage.length > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        // A separate layout keeps IME attributes, selection and native undo untouched.
        let outline = NSTextStorage(attributedString: storage)
        let manager = InkTextLayoutManager(); manager.pointSize = pointSize
        let container = NSTextContainer(containerSize: textContainers.first?.containerSize ?? NSSize(width: 100000, height: 100000))
        container.lineFragmentPadding = textContainers.first?.lineFragmentPadding ?? 0
        outline.addLayoutManager(manager); manager.addTextContainer(container)
        let all = NSRange(location: 0, length: outline.length)
        context.saveGState(); context.setAlpha(strength)
        for (color, width) in [(NSColor.white, CGFloat(4)), (.black, CGFloat(2))] {
            outline.addAttributes([.strokeColor: color, .strokeWidth: width * 100 / max(0.1, renderingScale()) / pointSize], range: all)
            manager.ensureLayout(for: container)
            let glyphs = NSIntersectionRange(range, manager.glyphRange(for: container))
            manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        }
        context.restoreGState()
    }
    override init() { super.init(); delegate = self; usesFontLeading = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        let height = InkTypography.lineHeight(pointSize)
        lineFragmentRect.pointee.size.height = height
        lineFragmentUsedRect.pointee.size.height = height
        baselineOffset.pointee = ceil(pointSize * 1.1)
        return true
    }
}

enum InkTypography {
    static func font(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    static func lineHeight(_ size: CGFloat) -> CGFloat { ceil(size * 1.45) }
    static func attributes(size: CGFloat, color: InkColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight(size); paragraph.maximumLineHeight = lineHeight(size)
        // Explicit spacing keeps mixed-script glyph positions identical in an
        // editable text view and a freshly created layout used for saved ink.
        return [.font: font(size), .foregroundColor: color.nsColor, .paragraphStyle: paragraph, .kern: 0]
    }
    static func layout(_ text: String, size: CGFloat, color: InkColor) -> (NSTextStorage, InkTextLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(string: text, attributes: attributes(size: size, color: color))
        let manager = InkTextLayoutManager(); manager.pointSize = size
        let container = NSTextContainer(containerSize: NSSize(width: 100000, height: 100000))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return (storage, manager, container)
    }
    static func editorSize(_ manager: NSLayoutManager, _ container: NSTextContainer, pointSize: CGFloat) -> NSSize {
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return NSSize(width: max(16, ceil(used.maxX) + 4), height: max(lineHeight(pointSize), ceil(used.maxY) + 3))
    }
    static func size(_ text: String, fontSize: CGFloat) -> NSSize {
        let (storage, manager, container) = layout(text, size: fontSize, color: InkColor.light[0])
        defer { _ = storage }
        return editorSize(manager, container, pointSize: fontSize)
    }
    static func draw(_ text: String, at point: NSPoint, size: CGFloat, color: InkColor, contrast: CGFloat = 0, scale: CGFloat = 1) {
        let (storage, manager, container) = layout(text, size: size, color: color)
        defer { _ = storage }
        manager.contrastStrength = { contrast }; manager.renderingScale = { scale }
        manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: point)
    }
}
