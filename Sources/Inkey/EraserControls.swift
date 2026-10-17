import AppKit

final class ToolButton: NSButton {
    var onRightClick: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let onRightClick { onRightClick(); return }
        super.mouseDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        if state == .on {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 3), xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}

final class EraserPreviewView: NSView {
    var diameter: Double = 24 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let size = min(120, max(4, diameter))
        let rect = NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)
        NSColor.labelColor.withAlphaComponent(0.035).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
        let circle = NSBezierPath(ovalIn: rect); circle.lineWidth = 1; circle.stroke()
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 1, y: bounds.midY - 1, width: 2, height: 2)).fill()
    }
}

final class EraserPanelController: NSViewController {
    let slider = NSSlider(value: 24, minValue: 4, maxValue: 120, target: nil, action: nil)
    let preview = EraserPreviewView(frame: .zero)
    let sizeLabel = NSTextField(labelWithString: "")
    var diameter: Double
    var onChange: ((Double) -> Void)?
    init(diameter: Double) { self.diameter = diameter; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 236, height: 230))
        let title = NSTextField(labelWithString: "橡皮擦")
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.frame = NSRect(x: 16, y: 201, width: 110, height: 18); view.addSubview(title)
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sizeLabel.alignment = .right; sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = NSRect(x: 142, y: 201, width: 78, height: 18); view.addSubview(sizeLabel)
        preview.frame = NSRect(x: 16, y: 64, width: 204, height: 130); view.addSubview(preview)
        slider.frame = NSRect(x: 14, y: 36, width: 208, height: 20)
        slider.target = self; slider.action = #selector(changed); slider.isContinuous = true
        slider.setAccessibilityLabel("Eraser diameter in screen points")
        view.addSubview(slider)
        let hint = NSTextField(labelWithString: "⌥ 拖动临时擦除")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.alignment = .center; hint.frame = NSRect(x: 16, y: 10, width: 204, height: 18); view.addSubview(hint)
        update(diameter)
    }
    func update(_ value: Double) {
        diameter = min(120, max(4, value.rounded()))
        slider.doubleValue = diameter; preview.diameter = diameter
        sizeLabel.stringValue = "\(Int(diameter)) pt"
    }
    @objc func changed() { update(slider.doubleValue); onChange?(diameter) }
}
