import AppKit

final class HueSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        let colors = (0...12).map { NSColor(hue: Double($0) / 12, saturation: 0.85, brightness: 0.95, alpha: 1) }
        NSGradient(colors: colors)?.draw(in: NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3), angle: 0)
    }
    override func drawKnob(_ knobRect: NSRect) {
        let rect = NSRect(x: knobRect.midX - 7, y: knobRect.midY - 7, width: 14, height: 14)
        NSColor.white.setFill(); NSBezierPath(ovalIn: rect).fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        let border = NSBezierPath(ovalIn: rect); border.lineWidth = 1; border.stroke()
        NSColor(hue: doubleValue, saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
    }
}

final class SwatchButton: NSButton {
    var inkColor = InkColor("303735") { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var isCustom = false
    var hovering = false
    override var acceptsFirstResponder: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false; title = ""
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let diameter: CGFloat = hovering ? 19 : 17
        let circle = NSRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
        inkColor.nsColor.setFill(); NSBezierPath(ovalIn: circle).fill()
        if selected {
            inkColor.nsColor.withAlphaComponent(0.65).setStroke()
            let outline = NSBezierPath(ovalIn: circle.insetBy(dx: -4, dy: -4)); outline.lineWidth = 1.3; outline.stroke()
        }
        if isCustom {
            let brightness = inkColor.red * 0.299 + inkColor.green * 0.587 + inkColor.blue * 0.114
            (brightness > 0.6 ? NSColor.black : NSColor.white).withAlphaComponent(0.85).setStroke()
            let plus = NSBezierPath(); plus.lineWidth = 1.25
            plus.move(to: NSPoint(x: bounds.midX - 3.5, y: bounds.midY)); plus.line(to: NSPoint(x: bounds.midX + 3.5, y: bounds.midY))
            plus.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 3.5)); plus.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 3.5)); plus.stroke()
        }
    }
}

final class ColorSquare: NSView {
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 0.5
    var brightness: CGFloat = 0.7
    var onChange: ((NSColor) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).addClip()
        NSGradient(starting: .white, ending: NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1))?.draw(in: bounds, angle: 0)
        NSGradient(starting: NSColor.black.withAlphaComponent(0), ending: .black)?.draw(in: bounds, angle: 90)
        let p = NSPoint(x: saturation * bounds.width, y: (1 - brightness) * bounds.height)
        NSColor.black.withAlphaComponent(0.4).setStroke()
        let outer = NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)); outer.lineWidth = 3; outer.stroke()
        NSColor.white.setStroke(); outer.lineWidth = 1.8; outer.stroke()
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); update(event) }
    override func mouseDragged(with event: NSEvent) { update(event) }
    private func update(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        saturation = min(1, max(0, p.x / bounds.width)); brightness = min(1, max(0, 1 - p.y / bounds.height))
        needsDisplay = true
        onChange?(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }
    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 0.1 : 0.01
        switch event.keyCode {
        case 123: saturation = max(0, saturation - step)
        case 124: saturation = min(1, saturation + step)
        case 125: brightness = max(0, brightness - step)
        case 126: brightness = min(1, brightness + step)
        default: super.keyDown(with: event); return
        }
        needsDisplay = true
        onChange?(NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }
}

final class ColorPanelController: NSViewController, NSTextFieldDelegate {
    let square = ColorSquare(frame: .zero)
    let hueSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let hexField = NSTextField()
    let preview = SwatchButton(frame: .zero)
    var color: InkColor
    var onPreview: ((InkColor) -> Void)?
    var onReplace: ((InkColor) -> Void)?
    var onClose: ((Bool) -> Void)?
    var recent: [InkColor]
    var recentButtons: [SwatchButton] = []
    init(color: InkColor, recent: [InkColor]) {
        self.color = color; self.recent = recent
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 304))
        square.frame = NSRect(x: 16, y: 140, width: 232, height: 148)
        square.setAccessibilityElement(true)
        square.setAccessibilityRole(.slider)
        square.setAccessibilityLabel("Color surface: left and right adjust saturation; up and down adjust brightness")
        view.addSubview(square)
        square.onChange = { [weak self] color in self?.update(InkColor(color), syncSquare: false) }
        hueSlider.frame = NSRect(x: 14, y: 108, width: 236, height: 20)
        hueSlider.cell = HueSliderCell()
        hueSlider.minValue = 0; hueSlider.maxValue = 1
        hueSlider.target = self; hueSlider.action = #selector(hueChanged)
        hueSlider.isContinuous = true; hueSlider.toolTip = "Hue"; hueSlider.setAccessibilityLabel("Hue")
        view.addSubview(hueSlider)
        preview.frame = NSRect(x: 12, y: 68, width: 36, height: 32); view.addSubview(preview)
        hexField.frame = NSRect(x: 52, y: 72, width: 134, height: 25)
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.delegate = self; hexField.target = self; hexField.action = #selector(hexChanged)
        hexField.setAccessibilityLabel("Hex color"); view.addSubview(hexField)
        let dropper = NSButton(image: NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Pick screen color")!, target: self, action: #selector(sample))
        dropper.frame = NSRect(x: 202, y: 70, width: 40, height: 28); dropper.bezelStyle = .texturedRounded
        view.addSubview(dropper)
        for (index, item) in recent.prefix(6).enumerated() {
            let button = SwatchButton(frame: NSRect(x: 16 + index * 38, y: 32, width: 32, height: 32))
            button.inkColor = item; button.tag = index; button.target = self; button.action = #selector(recentClicked(_:))
            button.toolTip = item.hex; button.setAccessibilityLabel("Recent color \(item.hex)")
            recentButtons.append(button); view.addSubview(button)
        }
        let replace = NSButton(title: "替换当前预设", target: self, action: #selector(replacePreset))
        replace.isBordered = false; replace.font = .systemFont(ofSize: 11)
        replace.frame = NSRect(x: 14, y: 5, width: 115, height: 23); view.addSubview(replace)
        let done = NSButton(title: "完成", target: self, action: #selector(done))
        done.bezelStyle = .rounded; done.frame = NSRect(x: 183, y: 4, width: 66, height: 25)
        view.addSubview(done)
        update(color, syncSquare: true, emit: false)
    }
    func update(_ value: InkColor, syncSquare: Bool, emit: Bool = true) {
        color = value; preview.inkColor = value; hexField.stringValue = value.hex
        if syncSquare, let rgb = value.nsColor.usingColorSpace(.deviceRGB) {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            square.hue = h; square.saturation = s; square.brightness = b; square.needsDisplay = true; hueSlider.doubleValue = Double(h)
        }
        if emit { onPreview?(value) }
    }
    @objc func hueChanged() {
        square.hue = hueSlider.doubleValue
        update(InkColor(NSColor(hue: square.hue, saturation: square.saturation, brightness: square.brightness, alpha: 1)), syncSquare: false)
    }
    @objc func hexChanged() {
        _ = acceptHex()
    }
    @discardableResult func acceptHex() -> Bool {
        guard let value = InkColor.parse(hexField.stringValue) else { NSSound.beep(); hexField.stringValue = color.hex; return false }
        update(value, syncSquare: true)
        return true
    }
    func controlTextDidChange(_ obj: Notification) {
        if let value = InkColor.parse(hexField.stringValue) { update(value, syncSquare: true) }
    }
    @objc func sample() {
        NSColorSampler().show { [weak self] value in
            guard let value else { return }
            self?.update(InkColor(value), syncSquare: true)
        }
    }
    @objc func recentClicked(_ sender: NSButton) { update(recent[sender.tag], syncSquare: true) }
    @objc func replacePreset() { onReplace?(color); onClose?(true) }
    @objc func done() { if acceptHex() { onClose?(true) } }
    override func cancelOperation(_ sender: Any?) { onClose?(false) }
}

final class PaletteView: NSView, NSPopoverDelegate {
    static let preferredWidth: CGFloat = 320
    let preferences: UserPreferences
    var colors: [InkColor] = InkColor.light
    var current = InkColor.light[0]
    var slot = 0
    var onColor: ((InkColor) -> Void)?
    var onRestoredColor: ((InkColor) -> Void)?
    var onBeginPreview: (() -> Void)?
    var onEndPreview: ((Bool, InkColor) -> Void)?
    var onRestoreFocus: (() -> Void)?
    var onEraser: ((Bool) -> Void)?
    var onEraserSize: ((Double) -> Void)?
    var eraserEnabled = false { didSet { updateToolButton() } }
    var eraserDiameter: Double = 24 {
        didSet { eraserController?.update(eraserDiameter) }
    }
    var paperIsDark: Bool?
    var popover: NSPopover?
    var eraserPopover: NSPopover?
    var hasPopover: Bool { popover != nil || eraserPopover != nil }
    private var eraserController: EraserPanelController?
    private var eraserButton: ToolButton!
    private var buttons: [SwatchButton] = []
    private var custom: SwatchButton!
    private var dragOrigin: NSPoint?
    private var originalFrame: NSPoint?
    private var initialColor: InkColor?
    private var acceptPreview = true
    private var previewController: ColorPanelController?
    private var dark = false
    private var previousPaper: Bool?
    private var recentColors: [InkColor] {
        get { (UserDefaults.standard.stringArray(forKey: "recentColors") ?? []).map(InkColor.init) }
        set { UserDefaults.standard.set(newValue.map(\.hex), forKey: "recentColors") }
    }
    override var acceptsFirstResponder: Bool { false }
    init(frame: NSRect, preferences: UserPreferences = UserPreferences()) {
        self.preferences = preferences
        super.init(frame: frame)
        wantsLayer = true
        let names = ["石墨", "朱红", "琥珀", "苔绿", "湖蓝", "鸢紫"]
        for index in 0..<6 {
            let button = SwatchButton(frame: NSRect(x: 20 + index * 34, y: 4, width: 34, height: 36))
            button.tag = index; button.target = self; button.action = #selector(chosen(_:))
            button.toolTip = "\(names[index]) · ⌥\(index + 1)"
            buttons.append(button); addSubview(button)
        }
        custom = SwatchButton(frame: NSRect(x: 233, y: 4, width: 34, height: 36))
        custom.isCustom = true; custom.target = self; custom.action = #selector(togglePicker)
        custom.toolTip = "自定义颜色 · ⇧⌘C"; custom.setAccessibilityLabel("Custom color")
        addSubview(custom)
        eraserButton = ToolButton(image: NSImage(systemSymbolName: "eraser", accessibilityDescription: "Eraser")!, target: self, action: #selector(toggleEraser))
        eraserButton.onDoubleClick = { [weak self] in self?.openEraserSizing() }
        eraserButton.frame = NSRect(x: 275, y: 4, width: 34, height: 36)
        eraserButton.isBordered = false
        eraserButton.toolTip = "单击切换橡皮，双击调节尺寸 · ⌥⌘E"
        addSubview(eraserButton)
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAppearance() }
    func refreshAppearance() {
        let newDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let previous = colors
        dark = paperIsDark ?? newDark
        let key = dark ? "darkPresets" : "lightPresets"
        let saved = UserDefaults.standard.stringArray(forKey: key)
        colors = saved?.count == 6 ? saved!.map(InkColor.init) : (dark ? InkColor.dark : InkColor.light)
        if previousPaper != dark {
            if let saved = preferences.ink(dark: dark) {
                slot = saved.slot; current = saved.isPreset ? colors[slot] : saved.color
            } else { slot = 0; current = colors[0] }
        } else if let index = previous.firstIndex(of: current) { current = colors[index] }
        previousPaper = dark
        onRestoredColor?(current)
        layer?.backgroundColor = (newDark ? NSColor(calibratedWhite: 0.18, alpha: 1) : NSColor(calibratedWhite: 0.998, alpha: 1)).cgColor
        layer?.cornerRadius = 14
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor; layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.08; layer?.shadowRadius = 12; layer?.shadowOffset = NSSize(width: 0, height: -3)
        updateButtons()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: 16, width: 2, height: 12), xRadius: 1, yRadius: 1).fill()
        NSColor.separatorColor.setFill(); NSRect(x: 228, y: 13, width: 1, height: 18).fill()
        NSRect(x: 272, y: 13, width: 1, height: 18).fill()
    }
    func updateButtons() {
        let names = ["石墨", "朱红", "琥珀", "苔绿", "湖蓝", "鸢紫"]
        let defaults = dark ? InkColor.dark : InkColor.light
        for (index, button) in buttons.enumerated() {
            button.inkColor = colors[index]; button.selected = !eraserEnabled && colors[index] == current
            let name = colors[index] == defaults[index] ? names[index] : colors[index].hex
            button.toolTip = "\(name) · ⌥\(index + 1)"
            button.setAccessibilityLabel("Preset \(index + 1), \(colors[index].hex)\(button.selected ? ", selected" : "")")
        }
        custom?.inkColor = current
    }
    private func updateToolButton() {
        eraserButton?.state = eraserEnabled ? .on : .off
        eraserButton?.contentTintColor = eraserEnabled ? .controlAccentColor : .secondaryLabelColor
        eraserButton?.setAccessibilityLabel(eraserEnabled ? "Eraser, selected" : "Eraser")
        eraserButton?.needsDisplay = true
        updateButtons()
    }
    func saveCurrentColor() {
        let index = colors.firstIndex(of: current)
        preferences.saveInk(SavedInk(color: current, slot: index ?? slot, isPreset: index != nil), dark: dark)
    }
    func choose(_ index: Int) {
        guard colors.indices.contains(index) else { return }
        closePicker(accept: true)
        slot = index; current = colors[index]; eraserEnabled = false
        onEraser?(false); updateButtons(); onColor?(current); saveCurrentColor(); onRestoreFocus?()
    }
    @objc func chosen(_ sender: NSButton) { choose(sender.tag) }
    @objc func togglePicker() {
        if popover != nil { closePicker(accept: true); return }
        closePicker(accept: true)
        eraserEnabled = false; onEraser?(false)
        initialColor = current; acceptPreview = true; onBeginPreview?()
        let controller = ColorPanelController(color: current, recent: recentColors)
        controller.onPreview = { [weak self] color in self?.current = color; self?.updateButtons(); self?.onColor?(color) }
        controller.onReplace = { [weak self] color in
            guard let self else { return }
            self.colors[self.slot] = color
            UserDefaults.standard.set(self.colors.map(\.hex), forKey: self.dark ? "darkPresets" : "lightPresets")
            self.updateButtons()
        }
        controller.onClose = { [weak self] accept in self?.closePicker(accept: accept) }
        let popup = NSPopover(); popup.contentViewController = controller
        popup.behavior = .semitransient; popup.delegate = self
        popover = popup; previewController = controller
        popup.show(relativeTo: custom.bounds, of: custom, preferredEdge: .maxY)
    }
    @objc func toggleEraser() {
        closePicker(accept: true)
        eraserEnabled.toggle(); onEraser?(eraserEnabled); onRestoreFocus?()
    }
    func openEraserSizing() {
        closePicker(accept: true); eraserEnabled = true; onEraser?(true)
        toggleEraserSize()
    }
    @objc func toggleEraserSize() {
        if eraserPopover != nil { closePicker(accept: true); return }
        closePicker(accept: true)
        let controller = EraserPanelController(diameter: eraserDiameter)
        controller.onChange = { [weak self] size in
            guard let self else { return }
            self.eraserDiameter = size; self.onEraserSize?(size)
        }
        let popup = NSPopover(); popup.behavior = .semitransient; popup.delegate = self
        popup.contentViewController = controller
        eraserPopover = popup; eraserController = controller
        popup.show(relativeTo: eraserButton.bounds, of: eraserButton, preferredEdge: .maxY)
    }
    func closePicker(accept: Bool) {
        acceptPreview = accept; popover?.performClose(nil); eraserPopover?.performClose(nil)
    }
    func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover, closed === eraserPopover {
            eraserPopover = nil; eraserController = nil; onRestoreFocus?(); return
        }
        guard let initialColor else { return }
        let accepted = acceptPreview
        if accepted {
            var recent = recentColors.filter { $0 != current }; recent.insert(current, at: 0)
            recentColors = Array(recent.prefix(6))
            saveCurrentColor()
        } else { current = initialColor }
        onEndPreview?(accepted, initialColor)
        self.initialColor = nil; popover = nil; previewController = nil
        updateButtons(); onRestoreFocus?()
    }
    func resetPresets() {
        UserDefaults.standard.removeObject(forKey: "lightPresets"); UserDefaults.standard.removeObject(forKey: "darkPresets")
        refreshAppearance()
    }
    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow; originalFrame = frame.origin
    }
    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let originalFrame, let superview else { return }
        let dx = event.locationInWindow.x - dragOrigin.x
        let dy = event.locationInWindow.y - dragOrigin.y
        let x = min(max(8, originalFrame.x + dx), max(8, superview.bounds.width - frame.width - 8))
        let y = min(max(8, originalFrame.y + (superview.isFlipped ? -dy : dy)), max(8, superview.bounds.height - frame.height - 8))
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    override func mouseUp(with event: NSEvent) {
        UserDefaults.standard.set([frame.origin.x, frame.origin.y], forKey: "palettePosition")
        dragOrigin = nil; originalFrame = nil
    }
}
